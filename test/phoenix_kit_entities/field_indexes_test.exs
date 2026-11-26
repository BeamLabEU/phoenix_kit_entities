defmodule PhoenixKitEntities.FieldIndexesTest do
  @moduledoc """
  Opt-in typed field indexes and the query helper that shares their
  expressions: the definition option and its validation, `sync/2`
  creating and dropping indexes, dirty values that neither fail a write
  nor match a filter, the filters themselves (numeric, date, text, on flat
  and multilang data), and the planner picking the index for a filter.

  The sandbox runs every test inside a transaction, so `sync/2` builds
  plainly here; the `CONCURRENTLY` path is the same statement with the
  keyword added.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.FieldIndexes
  alias PhoenixKitEntities.FieldQuery

  @fields [
    %{"type" => "text", "key" => "name", "label" => "Name"},
    %{"type" => "number", "key" => "price", "label" => "Price", "indexed" => "numeric"},
    %{"type" => "text", "key" => "city", "label" => "City", "indexed" => "text"},
    %{"type" => "date", "key" => "available", "label" => "Available", "indexed" => "date"},
    %{"type" => "number", "key" => "tonnes", "label" => "Tonnes"}
  ]

  setup do
    actor = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "fx_crane",
          display_name: "Crane",
          display_name_plural: "Cranes",
          fields_definition: @fields,
          status: "published",
          created_by_uuid: actor
        },
        actor_uuid: actor
      )

    %{entity: entity, actor: actor}
  end

  defp record!(entity, actor, title, data) do
    {:ok, record} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: title,
          slug: "#{title}-#{System.unique_integer([:positive])}",
          status: "published",
          created_by_uuid: actor
        },
        actor_uuid: actor
      )

    # The raw data straight into the column, so the dirty values a host's
    # import or an old row could hold are what the indexes and filters see.
    from(d in EntityData, where: d.uuid == ^record.uuid)
    |> Repo.update_all(set: [data: data])

    record
  end

  defp titles({:ok, records}), do: Enum.map(records, & &1.title)

  describe "the definition option" do
    test "specs/1 lists the indexed fields; index_type/1 reads atoms and strings", %{
      entity: entity
    } do
      assert FieldIndexes.specs(entity) == [
               {"price", "numeric"},
               {"city", "text"},
               {"available", "date"}
             ]

      assert FieldIndexes.index_type(%{"indexed" => :date}) == "date"
      assert FieldIndexes.index_type(%{"indexed" => "nope"}) == nil
      assert FieldIndexes.index_type(%{}) == nil
    end

    test "query_type/1 falls back to the field type", _ctx do
      assert FieldIndexes.query_type(%{"type" => "decimal"}) == "numeric"
      assert FieldIndexes.query_type(%{"type" => "date"}) == "date"
      assert FieldIndexes.query_type(%{"type" => "select"}) == "text"
      assert FieldIndexes.query_type(%{"type" => "number", "indexed" => "text"}) == "text"
    end

    test "an unknown index type is a changeset error", %{entity: entity} do
      bad = @fields ++ [%{"type" => "text", "key" => "x", "label" => "X", "indexed" => "gin"}]
      assert {:error, changeset} = Entities.update_entity(entity, %{fields_definition: bad})
      assert errors_on(changeset)[:fields_definition] |> Enum.any?(&(&1 =~ "gin"))
    end

    test "the index expression quotes the key as a literal" do
      assert FieldIndexes.expression("data", "o'brien", "text") ==
               "public.phoenix_kit_entities_idx_text(data, 'o''brien')"

      assert_raise ArgumentError, fn -> FieldIndexes.literal("a" <> <<0>>) end
    end
  end

  describe "sync/2" do
    test "creates the wanted indexes, is idempotent, and drops what is no longer wanted", %{
      entity: entity
    } do
      assert FieldIndexes.list(entity) == []

      assert {:ok, %{created: created, dropped: []}} = FieldIndexes.sync(entity)
      assert length(created) == 3

      listed = FieldIndexes.list(entity)

      assert Enum.map(listed, &{&1.key, &1.type}) |> Enum.sort() ==
               Enum.sort(FieldIndexes.specs(entity))

      assert Enum.all?(listed, & &1.valid?)
      assert {:ok, %{created: [], dropped: []}} = FieldIndexes.sync(entity)

      fields =
        Enum.map(@fields, fn
          %{"key" => "city"} = f -> Map.delete(f, "indexed")
          %{"key" => "price"} = f -> Map.put(f, "indexed", "text")
          f -> f
        end)

      {:ok, entity} = Entities.update_entity(entity, %{fields_definition: fields})
      assert {:ok, %{created: [_], dropped: dropped}} = FieldIndexes.sync(entity)
      assert length(dropped) == 2

      assert Enum.map(FieldIndexes.list(entity), &{&1.key, &1.type}) |> Enum.sort() ==
               [{"available", "date"}, {"price", "text"}]
    end

    test "a wanted index left without its comment (an interrupted build) is found by name",
         %{entity: entity} do
      name = FieldIndexes.index_name(entity.uuid, "price", "numeric")

      # What a build that died between CREATE and COMMENT leaves behind.
      Repo.query!(
        "CREATE INDEX #{name} ON public.phoenix_kit_entity_data " <>
          "(entity_uuid, (#{FieldIndexes.expression("data", "price", "numeric")}))"
      )

      assert FieldIndexes.list(entity) == []
      assert {:ok, %{created: created, dropped: []}} = FieldIndexes.sync(entity)
      refute name in created
      assert length(created) == 2

      assert %{key: "price", type: "numeric", valid?: true} =
               Enum.find(FieldIndexes.list(entity), &(&1.name == name))
    end

    test "list_uncommented/0 names a leftover no field asks for; sync leaves it alone",
         %{entity: entity} do
      name = FieldIndexes.index_name(entity.uuid, "gone", "numeric")
      Repo.query!("CREATE INDEX #{name} ON public.phoenix_kit_entity_data (entity_uuid)")

      assert %{name: ^name, valid?: true} =
               Enum.find(FieldIndexes.list_uncommented(), &(&1.name == name))

      {:ok, _} = FieldIndexes.sync(entity)
      assert Enum.any?(FieldIndexes.list_uncommented(), &(&1.name == name))
    end

    test "the stored definition is synced, not the struct passed in", %{entity: entity} do
      stale = %{entity | fields_definition: Enum.map(@fields, &Map.delete(&1, "indexed"))}
      assert {:ok, %{created: created}} = FieldIndexes.sync(stale)
      assert length(created) == 3
    end

    test "inside a transaction a sync another session holds the lock for is refused at once",
         %{entity: entity} do
      {:ok, conn} = Repo.config() |> Keyword.delete(:pool) |> Postgrex.start_link()
      key = "phoenix_kit_entities:field_index:" <> entity.uuid
      Postgrex.query!(conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])

      try do
        # (The sandbox's own transaction is not one `in_transaction?/0` sees.)
        assert {:ok, {:error, :sync_in_progress}} =
                 Repo.transaction(fn -> FieldIndexes.sync(entity) end)
      after
        Postgrex.query!(conn, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
        GenServer.stop(conn)
      end

      assert {:ok, %{created: [_, _, _]}} = FieldIndexes.sync(entity)
    end

    test "a deleted entity's indexes go with sync_all/1", %{entity: entity} do
      {:ok, _} = FieldIndexes.sync(entity)
      {:ok, _} = Entities.delete_entity(entity)
      assert length(FieldIndexes.list(entity.uuid)) == 3

      assert {:ok, %{dropped: 3}} = FieldIndexes.sync_all()
      assert FieldIndexes.list(entity.uuid) == []
    end

    test "an entity with no indexed field never schedules anything", %{actor: actor} do
      {:ok, plain} =
        Entities.create_entity(%{
          name: "fx_plain",
          display_name: "Plain",
          display_name_plural: "Plains",
          fields_definition: [%{"type" => "text", "key" => "a", "label" => "A"}],
          created_by_uuid: actor
        })

      assert FieldIndexes.specs(plain) == []
      assert {:ok, %{created: [], dropped: []}} = FieldIndexes.sync(plain)
    end

    test "names are deterministic and fit Postgres' identifier limit" do
      uuid = Ecto.UUID.generate()
      name = FieldIndexes.index_name(uuid, "price", "numeric")
      assert name == FieldIndexes.index_name(uuid, "price", "numeric")
      refute name == FieldIndexes.index_name(uuid, "price", "text")
      assert byte_size(name) <= 63
    end
  end

  describe "dirty values" do
    test "never fail a write under an index, and never match a filter", %{
      entity: entity,
      actor: actor
    } do
      {:ok, _} = FieldIndexes.sync(entity)

      record!(entity, actor, "good", %{
        "price" => 150,
        "available" => "2026-12-01",
        "city" => "Tallinn"
      })

      record!(entity, actor, "words", %{"price" => "call us", "available" => "soon"})
      record!(entity, actor, "comma", %{"price" => "12,5", "available" => "2026-02-30"})
      record!(entity, actor, "huge", %{"price" => "1e99999999", "available" => "9999-99-99"})
      record!(entity, actor, "object", %{"price" => %{"a" => 1}, "city" => ["x"]})
      record!(entity, actor, "long", %{"city" => String.duplicate("x", 5000)})

      assert titles(FieldQuery.list(entity, [{"price", :not_nil}])) == ["good"]
      assert titles(FieldQuery.list(entity, [{"available", :not_nil}])) == ["good"]

      assert titles(FieldQuery.list(entity, [{"city", :eq, String.duplicate("x", 5000)}])) ==
               ["long"]

      # Same first 255 characters, different value: the recheck refuses it.
      assert titles(
               FieldQuery.list(entity, [
                 {"city", :eq, String.duplicate("x", 255) <> "y"}
               ])
             ) == []
    end
  end

  describe "whitespace in stored values" do
    setup do
      # The functions as this branch defines them (the suite's DB may carry
      # an earlier body: the chain does not re-run a version it stamped).
      for stmt <- PhoenixKitEntities.Migrations.up_statements("public"),
          stmt =~ "CREATE OR REPLACE FUNCTION",
          do: Repo.query!(stmt)

      :ok
    end

    test "ASCII whitespace is skipped, a Unicode space is a dirty value, neither fails a write",
         %{entity: entity, actor: actor} do
      {:ok, _} = FieldIndexes.sync(entity)

      record!(entity, actor, "tab", %{"price" => "\t12\n", "available" => "\t2026-12-01"})

      record!(entity, actor, "emspace", %{
        "price" => "\u200312",
        "available" => "\u30002026-12-01"
      })

      assert titles(FieldQuery.list(entity, [{"price", :eq, 12}])) == ["tab"]
      assert titles(FieldQuery.list(entity, [{"available", :eq, "2026-12-01"}])) == ["tab"]
      assert titles(FieldQuery.list(entity, [{"price", :is_nil}])) == ["emspace"]
    end
  end

  describe "FieldQuery" do
    setup %{entity: entity, actor: actor} do
      {:ok, _} = FieldIndexes.sync(entity)

      record!(entity, actor, "small", %{
        "price" => 90,
        "city" => "Tartu",
        "available" => "2026-12-01",
        "tonnes" => "25"
      })

      record!(entity, actor, "medium", %{
        "price" => "150.50",
        "city" => "Tallinn",
        "available" => "2027-01-15",
        "tonnes" => 60
      })

      # Multilang: the value lives in the primary language's map.
      record!(entity, actor, "large", %{
        "_primary_language" => "et",
        "et" => %{"price" => "400", "city" => "Tallinn", "available" => "2027-03-01"},
        "en" => %{"price" => "999", "city" => "Somewhere"}
      })

      :ok
    end

    test "numeric comparisons, from flat and multilang data", %{entity: entity} do
      assert titles(FieldQuery.list(entity, [{"price", :lte, 150.5}], order_by: {"price", :asc})) ==
               ["small", "medium"]

      assert titles(FieldQuery.list(entity, [{"price", :gt, "100"}], order_by: {"price", :desc})) ==
               ["large", "medium"]

      assert titles(
               FieldQuery.list(entity, [{"price", :between, {100, 400}}],
                 order_by: {"price", :asc}
               )
             ) == ["medium", "large"]

      assert titles(
               FieldQuery.list(entity, [{"price", :in, [90, 400]}], order_by: {"price", :asc})
             ) ==
               ["small", "large"]

      # A secondary language's value is not the record's value.
      assert titles(FieldQuery.list(entity, [{"price", :eq, 999}])) == []
    end

    test "an unindexed number field compares as numeric too", %{entity: entity} do
      assert titles(FieldQuery.list(entity, [{"tonnes", :gte, 50}])) == ["medium"]
    end

    test "dates and text", %{entity: entity} do
      assert titles(
               FieldQuery.list(entity, [{"available", :gte, ~D[2027-01-01]}],
                 order_by: {"available", :asc}
               )
             ) == ["medium", "large"]

      assert titles(FieldQuery.list(entity, [{"city", :eq, "Tallinn"}, {"price", :lt, 200}])) == [
               "medium"
             ]

      assert titles(FieldQuery.list(entity, [{"city", :in, ["Tartu", "Narva"]}])) == ["small"]
      assert {:ok, 2} = FieldQuery.count(entity, [{"city", :eq, "Tallinn"}])
    end

    test "trashed records are left out unless asked for", %{entity: entity} do
      {:ok, [small]} = FieldQuery.list(entity, [{"city", :eq, "Tartu"}])
      {:ok, _} = EntityData.trash(small)
      assert titles(FieldQuery.list(entity, [{"city", :eq, "Tartu"}])) == []

      assert titles(FieldQuery.list(entity, [{"city", :eq, "Tartu"}], include_trashed: true)) ==
               ["small"]
    end

    test "errors name the problem", %{entity: entity} do
      assert {:error, {:unknown_field, "nope"}} = FieldQuery.list(entity, [{"nope", :eq, 1}])

      assert {:error, {:invalid_operator, "city", :lt}} =
               FieldQuery.list(entity, [{"city", :lt, "x"}])

      assert {:error, {:invalid_value, "price"}} = FieldQuery.list(entity, [{"price", :eq, "x"}])
      assert {:error, :entity_not_found} = FieldQuery.list("no_such_entity", [])
      assert {:ok, [_, _, _]} = FieldQuery.list("fx_crane", [])
    end

    test "limit and offset must be integers; NaN and out-of-range numbers are invalid values",
         %{entity: entity} do
      assert {:error, {:invalid_option, :offset}} =
               FieldQuery.list(entity, [], offset: "0 + (SELECT 1/0)")

      assert {:error, {:invalid_option, :limit}} = FieldQuery.list(entity, [], limit: "10")
      assert {:ok, [_]} = FieldQuery.list(entity, [], limit: 1, offset: 1)

      assert {:error, {:invalid_value, "price"}} =
               FieldQuery.list(entity, [{"price", :lte, "NaN"}])

      assert {:error, {:invalid_value, "price"}} =
               FieldQuery.list(entity, [{"price", :lte, Decimal.new("Infinity")}])

      assert {:error, {:invalid_value, "price"}} =
               FieldQuery.list(entity, [{"price", :lte, Integer.pow(10, 2000)}])

      # Bounded without walking the digits.
      {micros, result} =
        :timer.tc(fn -> FieldQuery.list(entity, [{"price", :lte, Integer.pow(7, 100_000)}]) end)

      assert result == {:error, {:invalid_value, "price"}}
      assert micros < 1_000_000
    end

    test "a status may be an atom", %{entity: entity} do
      assert {:ok, [_, _, _]} = FieldQuery.list(entity, [], status: :published)
      assert {:ok, [_, _, _]} = FieldQuery.list(entity, [], status: [:published, "draft"])
      assert {:ok, []} = FieldQuery.list(entity, [], status: %{})
    end

    test "the planner uses the index for every operator shape and type", %{entity: entity} do
      Repo.query!("SET LOCAL enable_seqscan = off")
      # Three rows: the (entity_uuid, position) index is as cheap as any, so
      # it goes for this test (the sandbox rolls the DROP back) — what is
      # pinned is that the field's index MATCHES the query's expression.
      Repo.query!("DROP INDEX IF EXISTS public.phoenix_kit_entity_data_entity_position_idx")

      for {filters, key, type} <- [
            {[{"price", :between, {100, 200}}], "price", "numeric"},
            {[{"price", :in, [90, 400]}], "price", "numeric"},
            {[{"available", :gte, "2027-01-01"}], "available", "date"},
            {[{"available", :between, {"2026-01-01", "2026-12-31"}}], "available", "date"},
            {[{"city", :eq, "Tallinn"}], "city", "text"},
            {[{"city", :in, ["Tallinn", "Tartu"]}], "city", "text"}
          ] do
        {:ok, sql, params} = FieldQuery.build(entity, filters)
        %{rows: rows} = Repo.query!("EXPLAIN " <> sql, params)
        plan = Enum.map_join(rows, "\n", &hd/1)
        assert plan =~ FieldIndexes.index_name(entity.uuid, key, type), inspect(filters) <> plan
      end
    end

    test "the planner uses the field's index", %{entity: entity} do
      {:ok, sql, params} = FieldQuery.build(entity, [{"price", :lte, 200}])
      Repo.query!("SET LOCAL enable_seqscan = off")
      %{rows: rows} = Repo.query!("EXPLAIN " <> sql, params)
      plan = Enum.map_join(rows, "\n", &hd/1)
      [{_, "numeric"} | _] = FieldIndexes.specs(entity)
      assert plan =~ FieldIndexes.index_name(entity.uuid, "price", "numeric"), plan
    end
  end
end
