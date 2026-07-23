defmodule PhoenixKitEntities.FormBuilderRenderTest do
  @moduledoc """
  Coverage push for `PhoenixKitEntities.FormBuilder.build_field/3` —
  exercises every type's render path. Validation is already covered
  by `form_builder_validation_test.exs` + `form_builder_multilang_test.exs`;
  here we just confirm the render branches don't crash and emit
  type-appropriate markup.
  """
  use PhoenixKitEntities.DataCase, async: false

  import Phoenix.LiveViewTest

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.FormBuilder

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "fb_render",
          display_name: "FB Render",
          display_name_plural: "FB Render",
          fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, record} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "Render fixture",
          slug: "render-fixture",
          status: "draft",
          data: %{},
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, record: record, actor_uuid: actor_uuid}
  end

  defp render_field(type, opts \\ %{}) do
    field =
      Map.merge(
        %{
          "type" => type,
          "key" => "field_#{type}",
          "label" => "Label #{type}",
          "required" => false
        },
        opts
      )

    record = %EntityData{data: %{}}
    changeset = Ecto.Changeset.cast(record, %{}, [])

    rendered = FormBuilder.build_field(field, changeset)
    rendered_to_string(rendered)
  end

  describe "build_field/3 — every type renders without crashing" do
    test "text" do
      html = render_field("text")
      assert html =~ "input"
      assert html =~ "type=\"text\""
    end

    test "textarea" do
      html = render_field("textarea")
      assert html =~ "textarea"
    end

    test "email" do
      html = render_field("email")
      assert html =~ "input"
      assert html =~ "type=\"email\""
    end

    test "url" do
      html = render_field("url")
      assert html =~ "input"
      assert html =~ "type=\"url\""
    end

    test "rich_text" do
      html = render_field("rich_text")
      assert html =~ "textarea" or html =~ "rich_text"
    end

    test "number" do
      html = render_field("number")
      assert html =~ "input"
      assert html =~ "type=\"number\""
    end

    test "boolean" do
      html = render_field("boolean")
      assert html =~ "checkbox" or html =~ "toggle"
    end

    test "date" do
      html = render_field("date")
      assert html =~ "input"
      assert html =~ "type=\"date\""
    end

    test "select with options" do
      html = render_field("select", %{"options" => ["A", "B", "C"]})
      assert html =~ "select"
      assert html =~ ">A<" or html =~ "value=\"A\""
    end

    test "radio with options" do
      html = render_field("radio", %{"options" => ["X", "Y"]})
      assert html =~ "radio" or html =~ "type=\"radio\""
    end

    test "checkbox with options" do
      html = render_field("checkbox", %{"options" => ["red", "blue"]})
      assert html =~ "checkbox" or html =~ "type=\"checkbox\""
    end

    test "image" do
      html = render_field("image")
      assert is_binary(html)
      refute html == ""
    end

    test "file" do
      html = render_field("file")
      assert html =~ "file" or html =~ "upload"
    end

    test "relation" do
      html = render_field("relation", %{"relation_entity" => "fb_render"})
      assert is_binary(html)
    end

    test "unknown type falls through to default render" do
      html = render_field("unknown_type_#{System.unique_integer([:positive])}")
      assert is_binary(html)
    end
  end

  describe "build_fields/3 — orchestrator" do
    test "renders all fields wrapped per language", ctx do
      changeset = Ecto.Changeset.cast(ctx.record, %{}, [])
      rendered = FormBuilder.build_fields(ctx.entity, changeset)
      html = rendered_to_string(rendered)
      assert html =~ "form-field-wrapper"
      # Lang suffix in the per-field wrapper id.
      assert html =~ "entity-field-title-primary"
    end

    test "with lang_code opt, wrapper id reflects the locale", ctx do
      changeset = Ecto.Changeset.cast(ctx.record, %{}, [])
      rendered = FormBuilder.build_fields(ctx.entity, changeset, lang_code: "es")
      html = rendered_to_string(rendered)
      assert html =~ "entity-field-title-es"
    end

    test "with id_prefix opt, wrapper id folds in the prefix", ctx do
      changeset = Ecto.Changeset.cast(ctx.record, %{}, [])
      rendered = FormBuilder.build_fields(ctx.entity, changeset, id_prefix: "abc")
      html = rendered_to_string(rendered)
      assert html =~ ~s(id="entity-field-abc-title-primary")
    end
  end

  describe "get_field_value/2" do
    test "returns nil when data is empty", ctx do
      changeset = Ecto.Changeset.cast(ctx.record, %{}, [])
      assert FormBuilder.get_field_value(changeset, "missing") == nil
    end

    test "returns the value when data has the key" do
      record = %EntityData{data: %{"foo" => "bar"}}
      changeset = Ecto.Changeset.cast(record, %{}, [])
      assert FormBuilder.get_field_value(changeset, "foo") == "bar"
    end

    test "returns nil when data field is nil" do
      record = %EntityData{data: nil}
      changeset = Ecto.Changeset.cast(record, %{}, [])
      assert FormBuilder.get_field_value(changeset, "anything") == nil
    end
  end
end
