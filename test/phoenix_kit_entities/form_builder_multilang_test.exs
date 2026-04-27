defmodule PhoenixKitEntities.FormBuilderMultilangTest do
  use PhoenixKitEntities.DataCase, async: true

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.FormBuilder

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "fb_ml_test",
          display_name: "FB ML Test",
          display_name_plural: "FB ML Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"},
            %{"type" => "boolean", "key" => "active", "label" => "Active"},
            %{
              "type" => "select",
              "key" => "color",
              "label" => "Color",
              "options" => ["red", "blue"]
            }
          ],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    multilang_data = %{
      "_primary_language" => "en-US",
      "en-US" => %{"name" => "Acme", "active" => true, "color" => "red"},
      "es-ES" => %{"name" => "Acme España"}
    }

    {:ok, record} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "Test",
          slug: "test",
          data: multilang_data,
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    changeset = EntityData.change(record)

    {:ok, entity: entity, record: record, changeset: changeset, actor_uuid: actor_uuid}
  end

  describe "build_fields/3 — multilang rendering" do
    test "primary tab shows the primary language values", ctx do
      html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, lang_code: "en-US")
        |> render_html()

      # Per-language wrapper id matches "primary" suffix on primary tab.
      assert html =~ ~s|id="entity-field-name-en-US"|

      # Boolean field rendered with `checked` for primary's true value.
      assert html =~ ~r|type="checkbox"[^>]*checked|

      # Select field rendered with selected=red.
      assert html =~ ~r|<option value="red"[^>]*selected|
    end

    test "secondary tab with override shows ONLY the override (non-text inherited)", ctx do
      html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, lang_code: "es-ES")
        |> render_html()

      # Wrapper id is per-language so morphdom replaces the input on tab switch.
      assert html =~ ~s|id="entity-field-name-es-ES"|

      # Spanish has its OWN "name" override, so the input shows it.
      assert html =~ ~s|value="Acme España"|

      # Spanish has no "active" override → boolean must NOT be checked.
      # Pre-fix: `get_language_data` merged primary in → checked=true → buggy.
      # Post-fix: `get_raw_language_data` → no override → unchecked.
      refute html =~ ~r|name="[^"]*\[active\]"[^>]*checked|

      # Spanish has no "color" override → no <option> should be selected.
      # (Pre-fix: red would inherit; post-fix: nothing selected.)
      refute html =~ ~r|<option value="red"[^>]*selected|
    end

    test "secondary tab with no overrides at all shows empty fields", ctx do
      html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, lang_code: "fr-FR")
        |> render_html()

      # FR has no entry in multilang data → all fields empty/unchecked.
      refute html =~ ~r|name="[^"]*\[name\]"[^>]*value="Acme"|
      refute html =~ ~r|name="[^"]*\[active\]"[^>]*checked|
      refute html =~ ~r|<option value="red"[^>]*selected|

      # Wrapper id includes the locale.
      assert html =~ ~s|id="entity-field-name-fr-FR"|
    end

    test "primary placeholder is set on secondary tabs (UX hint)", ctx do
      html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, lang_code: "fr-FR")
        |> render_html()

      # Text field on secondary tab shows primary value as placeholder.
      assert html =~ ~s|placeholder="Acme"|
    end

    test "wrapper id changes between language tabs (rekeying for morphdom)", ctx do
      en_html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, lang_code: "en-US")
        |> render_html()

      es_html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, lang_code: "es-ES")
        |> render_html()

      assert en_html =~ ~s|id="entity-field-name-en-US"|
      assert es_html =~ ~s|id="entity-field-name-es-ES"|
      refute en_html =~ ~s|id="entity-field-name-es-ES"|
      refute es_html =~ ~s|id="entity-field-name-en-US"|
    end

    test "no lang_code (multilang disabled) uses 'primary' suffix", ctx do
      # When called without lang_code, the wrapper still gets a stable id.
      html =
        FormBuilder.build_fields(ctx.entity, ctx.changeset, [])
        |> render_html()

      assert html =~ ~s|id="entity-field-name-primary"|
    end
  end

  # ── helpers ──────────────────────────────────────────────────

  # Renders a Phoenix.LiveView.Rendered struct (returned by ~H sigils) into
  # an iodata HTML string for regex assertions.
  defp render_html(rendered) do
    rendered
    |> Phoenix.LiveViewTest.rendered_to_string()
  end
end
