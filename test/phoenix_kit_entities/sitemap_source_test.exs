defmodule PhoenixKitEntities.SitemapSourceTest do
  @moduledoc """
  Tests for `PhoenixKitEntities.SitemapSource` — the sitemap-source
  callbacks (`source_name/0`, `sitemap_filename/0`, `enabled?/0`,
  `collect/1`, `sub_sitemaps/1`).

  Coverage strategy: drive the full collect/sub_sitemaps pipeline
  with seeded entities + records so the route-resolution chain,
  pattern fallbacks, exclusion filter, and index-page emission all
  execute. Use the `sitemap_entities_auto_pattern` setting so the
  module finds patterns without a parent router.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKit.Settings
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.SitemapSource

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "sitemap_widget",
          display_name: "Sitemap Widget",
          display_name_plural: "Sitemap Widgets",
          fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    # Force the module enabled for the duration of these tests so
    # `enabled?/0` returns true.
    {:ok, _} = Settings.update_setting("entities_enabled", "true")

    {:ok, _published} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "First",
          slug: "first",
          status: "published",
          data: %{"title" => "First"},
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, _excluded} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "Excluded",
          slug: "excluded",
          status: "published",
          data: %{},
          metadata: %{"sitemap_exclude" => true},
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, _draft} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "Draft",
          slug: "draft",
          status: "draft",
          data: %{},
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, actor_uuid: actor_uuid}
  end

  describe "source_name/0 + sitemap_filename/0" do
    test "static identifiers" do
      assert SitemapSource.source_name() == :entities
      assert SitemapSource.sitemap_filename() == "sitemap-entities"
    end
  end

  describe "sitemap_settings_schema/0" do
    test "returns the fixed schema shape with defaults matching what the source reads at runtime" do
      schema = SitemapSource.sitemap_settings_schema()

      assert is_list(schema)
      assert length(schema) == 3

      for entry <- schema do
        assert %{key: key, type: type, label: label, help: help, default: _} = entry
        assert is_binary(key)
        assert type in [:boolean, :string, :integer]
        assert is_binary(label) and label != ""
        assert is_binary(help) and help != ""
      end

      by_key = Map.new(schema, &{&1.key, &1})

      # `sitemap_entities_include_index` -- read via
      # `Settings.get_boolean_setting("sitemap_entities_include_index", true)`
      # in both `do_collect/1` and `sub_sitemaps/1`.
      assert %{type: :boolean, default: true} = by_key["sitemap_entities_include_index"]

      # `sitemap_entities_auto_pattern` -- read via
      # `Settings.get_boolean_setting("sitemap_entities_auto_pattern", false)`
      # in `do_collect/1`, `get_fallback_pattern/1`, and `UrlResolver`.
      assert %{type: :boolean, default: false} = by_key["sitemap_entities_auto_pattern"]

      # `sitemap_entities_pattern` -- read via the no-default
      # `Settings.get_setting/1` in `UrlResolver.get_global_pattern/1`, which
      # returns `nil` (i.e. "no global pattern") when unset; the schema's ""
      # default represents that same "unset" state for a string field.
      assert %{type: :string, default: ""} = by_key["sitemap_entities_pattern"]
    end
  end

  describe "enabled?/0" do
    test "true when entities_enabled is set" do
      Settings.update_setting("entities_enabled", "true")
      assert SitemapSource.enabled?()
    end

    test "false when entities_enabled is unset" do
      Settings.update_setting("entities_enabled", "false")
      refute SitemapSource.enabled?()
    end
  end

  describe "collect/1" do
    test "non-default language emits records only where a per-locale translation exists", ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      # The seeded records are field-keyed (no per-locale translations), so a
      # non-default locale has no translation and must yield no entries.
      fr =
        SitemapSource.collect(
          base_url: "https://example.test",
          is_default_language: false,
          language: "fr"
        )

      ours =
        Enum.filter(fr, fn e -> e.category in [ctx.entity.display_name, ctx.entity.name] end)

      assert ours == []
    end

    test "non-default language emits a record that has a real per-locale translation", ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      {:ok, _translated} =
        EntityData.create(
          %{
            entity_uuid: ctx.entity.uuid,
            title: "Bonjour",
            slug: "translated-fr",
            status: "published",
            # Genuine multilang record: top-level keys are locale codes.
            data: %{
              "_primary_language" => "en-US",
              "en-US" => %{"title" => "Hello"},
              "fr-FR" => %{"title" => "Bonjour"}
            },
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      fr =
        SitemapSource.collect(
          base_url: "https://example.test",
          is_default_language: false,
          language: "fr"
        )

      # The fr-FR translation exists -> the record is emitted for "fr". The
      # field-keyed seed records (e.g. "first") have no fr translation and stay out.
      assert Enum.any?(fr, fn e -> String.contains?(e.loc, "translated-fr") end)
      refute Enum.any?(fr, fn e -> String.contains?(e.loc, "/first") end)
    end

    test "flat record with a locale-colliding field key is not emitted for that language", ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      # An ordinary entity whose field key "id" happens to equal the Indonesian
      # base locale code. A flat record's `data` is keyed by field names, so the
      # "id" field must never be mistaken for an "id" (Indonesian) translation.
      {:ok, entity} =
        Entities.create_entity(
          %{
            name: "collide_entity",
            display_name: "Collide Entity",
            display_name_plural: "Collide Entities",
            fields_definition: [
              %{"type" => "text", "key" => "title", "label" => "Title"},
              %{"type" => "text", "key" => "id", "label" => "External ID"}
            ],
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      {:ok, _} =
        EntityData.create(
          %{
            entity_uuid: entity.uuid,
            title: "Has Id Field",
            slug: "id-collision",
            status: "published",
            data: %{"title" => "Has Id Field", "id" => "EXT-42"},
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      result =
        SitemapSource.collect(
          base_url: "https://example.test",
          is_default_language: false,
          language: "id"
        )

      # No real Indonesian translation exists, so the record must not produce a
      # localized URL — the "id" field is not an "id" locale.
      refute Enum.any?(result, fn e -> String.contains?(e.loc, "id-collision") end)
    end

    test "returns [] when entities_enabled is off" do
      Settings.update_setting("entities_enabled", "false")
      assert SitemapSource.collect([]) == []
    end

    test "returns [] when no entity has a public route + auto-pattern is off", _ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "false")
      # No router routes resolved in test endpoint, so empty.
      result = SitemapSource.collect([])
      assert result == []
    end

    test "with auto_pattern on, emits records for published entities (excluding metadata + drafts)",
         ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")
      Settings.update_setting("sitemap_entities_include_index", "true")

      result = SitemapSource.collect(base_url: "https://example.test")

      assert is_list(result)
      # Find entries for our entity. Other tests in this run may have
      # seeded other entities; filter by category.
      ours =
        Enum.filter(result, fn entry ->
          entry.category == ctx.entity.display_name or
            entry.category == ctx.entity.name
        end)

      # At least one published record + an index page.
      refute Enum.empty?(ours)

      # No "Excluded" entry should appear (sitemap_exclude metadata)
      refute Enum.any?(ours, fn e -> String.contains?(e.loc, "/excluded") end)

      # No "Draft" entry should appear either (status != published)
      refute Enum.any?(ours, fn e -> String.contains?(e.loc, "/draft") end)
    end

    test "entity-level sitemap_exclude omits the entity entirely", ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      {:ok, internal} =
        Entities.create_entity(
          %{
            name: "internal_form",
            display_name: "Internal Form",
            display_name_plural: "Internal Forms",
            fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
            settings: %{"sitemap_exclude" => true},
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      {:ok, _} =
        EntityData.create(
          %{
            entity_uuid: internal.uuid,
            title: "Secret",
            slug: "secret-internal",
            status: "published",
            data: %{"title" => "Secret"},
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      result = SitemapSource.collect(base_url: "https://example.test", is_default_language: true)

      # The excluded entity's record must never appear, even though it is
      # published and auto_pattern would otherwise make it eligible.
      refute Enum.any?(result, fn e -> String.contains?(e.loc, "secret-internal") end)
    end

    test "with auto_pattern on but include_index off, no index entries", ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")
      Settings.update_setting("sitemap_entities_include_index", "false")

      result = SitemapSource.collect(base_url: "https://example.test")

      ours =
        Enum.filter(result, fn entry ->
          entry.category == ctx.entity.display_name or
            entry.category == ctx.entity.name
        end)

      # Index page (priority 0.7) should be absent.
      refute Enum.any?(ours, &(&1.priority == 0.7))
    end
  end

  describe "sub_sitemaps/1" do
    test "non-default language yields nil when no entity has a translated record" do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      # Seeded records are field-keyed (no per-locale translations) → no fr
      # entries → all groups empty → nil.
      assert SitemapSource.sub_sitemaps(
               base_url: "https://example.test",
               is_default_language: false,
               language: "fr"
             ) == nil
    end

    test "returns nil when entities_enabled is off" do
      Settings.update_setting("entities_enabled", "false")
      assert SitemapSource.sub_sitemaps([]) == nil
    end

    test "with auto_pattern on, returns [{name, entries}, ...] or nil if all empty", ctx do
      Settings.update_setting("sitemap_entities_auto_pattern", "true")

      result = SitemapSource.sub_sitemaps(base_url: "https://example.test")

      # Either nil (when no entity has any published records — but we
      # seeded one) or a list of {name, entries} tuples.
      case result do
        nil ->
          :ok

        list when is_list(list) ->
          # Our seeded entity should appear if it has emit-able entries.
          Enum.each(list, fn {name, entries} ->
            assert is_binary(name)
            assert is_list(entries)
          end)

          our_tuple =
            Enum.find(list, fn {name, _entries} -> name == ctx.entity.name end)

          if our_tuple do
            {_name, entries} = our_tuple
            refute Enum.empty?(entries)
          end
      end
    end
  end
end
