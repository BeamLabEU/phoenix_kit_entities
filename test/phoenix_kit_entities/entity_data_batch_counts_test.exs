defmodule PhoenixKitEntities.EntityDataBatchCountsTest do
  @moduledoc """
  `counts_by_entities/2` exists so listings showing counts for a page of
  entities run ONE grouped query — and so its tally matches what viewers
  actually show (`exclude_statuses:` mirrors their archived filtering,
  trashed is excluded like `list_by_entity/2`).
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor = Ecto.UUID.generate()

    {:ok, a} =
      Entities.create_entity(
        %{
          name: "batch_count_a",
          display_name: "Alpha",
          display_name_plural: "Alphas",
          fields_definition: [],
          created_by_uuid: actor
        },
        actor_uuid: actor
      )

    {:ok, b} =
      Entities.create_entity(
        %{
          name: "batch_count_b",
          display_name: "Beta",
          display_name_plural: "Betas",
          fields_definition: [],
          created_by_uuid: actor
        },
        actor_uuid: actor
      )

    make = fn entity, title, status ->
      {:ok, rec} =
        EntityData.create(%{
          entity_uuid: entity.uuid,
          title: title,
          slug: String.downcase(String.replace(title, " ", "-")),
          status: status,
          data: %{},
          created_by_uuid: actor
        })

      rec
    end

    %{a: a, b: b, actor: actor, make: make}
  end

  test "one grouped query, per-entity tallies, absent entities absent", %{a: a, b: b, make: make} do
    make.(a, "A One", "published")
    make.(a, "A Two", "draft")
    make.(b, "B One", "published")

    counts = EntityData.counts_by_entities([a.uuid, b.uuid, Ecto.UUID.generate()])
    assert counts[a.uuid] == 2
    assert counts[b.uuid] == 1
    assert map_size(counts) == 2

    assert EntityData.counts_by_entities([]) == %{}
  end

  test "exclude_statuses mirrors viewer filtering", %{a: a, make: make} do
    make.(a, "Live", "published")
    make.(a, "Sleeping", "archived")

    assert EntityData.counts_by_entities([a.uuid]) == %{a.uuid => 2}

    assert EntityData.counts_by_entities([a.uuid], exclude_statuses: ["archived"]) ==
             %{a.uuid => 1}
  end

  describe "entity_uuids_matching_title/3" do
    test "one query answers 'which of these contain a match?'", %{a: a, b: b, make: make} do
      make.(a, "Oak", "published")
      make.(a, "Walnut", "published")
      make.(b, "Steel", "published")

      assert EntityData.entity_uuids_matching_title([a.uuid, b.uuid], "oak") == [a.uuid]

      # Case-insensitive, substring, and scoped to the given uuids.
      assert EntityData.entity_uuids_matching_title([a.uuid], "WALN") == [a.uuid]
      assert EntityData.entity_uuids_matching_title([b.uuid], "oak") == []
      assert EntityData.entity_uuids_matching_title([], "oak") == []
    end

    test "blank terms match nothing; statuses filter like the viewers", %{a: a, make: make} do
      make.(a, "Archived Oak", "archived")

      assert EntityData.entity_uuids_matching_title([a.uuid], "   ") == []
      assert EntityData.entity_uuids_matching_title([a.uuid], "oak") == [a.uuid]

      assert EntityData.entity_uuids_matching_title([a.uuid], "oak",
               exclude_statuses: ["archived"]
             ) == []
    end

    test "a translated title matches too", %{a: a, b: b, actor: actor, make: make} do
      # Translations live in the record's data JSONB, so searching the
      # Estonian label has to find the record whose column says "Oak".
      {:ok, _} =
        EntityData.create(%{
          entity_uuid: a.uuid,
          title: "Oak",
          slug: "oak",
          status: "published",
          data: %{"et" => %{"_title" => "Tamm"}},
          created_by_uuid: actor
        })

      make.(b, "Steel", "published")

      assert EntityData.entity_uuids_matching_title([a.uuid, b.uuid], "Tamm") == [a.uuid]
      assert EntityData.entity_uuids_matching_title([a.uuid, b.uuid], "oak") == [a.uuid]
    end

    test "LIKE metacharacters are literal", %{a: a, b: b, actor: actor, make: make} do
      # Built inline: the slug format rejects "%", but the TITLE may
      # carry it — which is exactly the case being pinned.
      {:ok, _} =
        EntityData.create(%{
          entity_uuid: a.uuid,
          title: "50% gloss",
          slug: "fifty-gloss",
          status: "published",
          data: %{},
          created_by_uuid: actor
        })

      make.(b, "plain", "published")

      # "%" must not act as a wildcard: it matches the one real title.
      assert EntityData.entity_uuids_matching_title([a.uuid, b.uuid], "0% gl") == [a.uuid]

      # A bare "%" would match everything if unescaped.
      assert EntityData.entity_uuids_matching_title([b.uuid], "%") == []
    end
  end

  test "list_by_entity honors :limit", %{a: a, make: make} do
    for i <- 1..4, do: make.(a, "Rec #{i}", "published")

    assert length(EntityData.list_by_entity(a.uuid, limit: 2)) == 2
    assert length(EntityData.list_by_entity(a.uuid)) == 4
  end

  describe "list_by_entities/2" do
    test "groups per entity and leaves empty ones out", %{a: a, b: b, make: make} do
      make.(a, "A One", "published")
      make.(a, "A Two", "published")
      make.(b, "B One", "published")

      rows = EntityData.list_by_entities([a.uuid, b.uuid, Ecto.UUID.generate()])

      assert length(rows[a.uuid]) == 2
      assert length(rows[b.uuid]) == 1
      assert map_size(rows) == 2
      assert EntityData.list_by_entities([]) == %{}
    end

    test ":limit is exact even when the excluded rows come first", %{a: a, make: make} do
      # The point of filtering in SQL. Limiting first and dropping
      # archived after returns 1 of the 2 asked for, and a caller
      # showing "the first 2 values" then shows one and looks done.
      for i <- 1..6, do: make.(a, "Old #{i}", "archived")
      for i <- 1..3, do: make.(a, "Live #{i}", "published")

      rows = EntityData.list_by_entities([a.uuid], exclude_statuses: ["archived"], limit: 2)

      assert length(rows[a.uuid]) == 2
      assert Enum.all?(rows[a.uuid], &(&1.status == "published"))
    end

    test "order matches list_by_entity, in both sort modes", %{a: a, actor: actor, make: make} do
      # The batch sorts already-loaded rows in Elixir; the single-entity
      # path sorts in SQL. A set whose values are hand-ordered has to come
      # back the same way from both, and only this holds them together.
      for i <- 1..4, do: make.(a, "Rec #{i}", "published")

      assert ids(EntityData.list_by_entities([a.uuid])[a.uuid]) ==
               ids(EntityData.list_by_entity(a.uuid))

      {:ok, _} =
        Entities.update_entity(a, %{settings: Map.put(a.settings || %{}, "sort_mode", "manual")},
          actor_uuid: actor
        )

      # Positions out of insertion order, and one left unset — nulls last.
      [r1, r2, r3, r4] = EntityData.list_by_entity(a.uuid)

      for {rec, pos} <- [{r1, 3}, {r2, 1}, {r3, nil}, {r4, 2}] do
        {:ok, _} = EntityData.update(rec, %{position: pos})
      end

      manual = EntityData.list_by_entity(a.uuid)
      assert ids(EntityData.list_by_entities([a.uuid])[a.uuid]) == ids(manual)
      assert Enum.map(manual, & &1.position) == [1, 2, 3, nil]
    end
  end

  defp ids(records), do: Enum.map(records, & &1.uuid)
end
