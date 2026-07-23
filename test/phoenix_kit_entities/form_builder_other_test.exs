defmodule PhoenixKitEntities.FormBuilderOtherTest do
  @moduledoc """
  `allow_other` lets radio/select/checkbox fields offer a free-text "Muu"
  (Other) option alongside their fixed `options` list. Covers both halves
  of the feature:

  - `merge_other_params/2` — pure param normalization (sentinel → free text)
  - `build_field/3` — rendering the extra option + companion text input
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixKitEntities.FormBuilder

  @field %{
    "type" => "radio",
    "key" => "varv",
    "label" => "Värv",
    "options" => ["Must", "Valge"],
    "allow_other" => true
  }

  defp changeset(data),
    do: Ecto.Changeset.cast(%PhoenixKitEntities.EntityData{data: data}, %{}, [])

  # radio/checkbox render `value="__other__"` and `checked` as separate
  # (non-adjacent) HTML attributes — pull out just that `<input>` tag so
  # assertions don't depend on attribute ordering.
  defp other_input_tag(html) do
    case Regex.run(~r/<input[^>]*value="__other__"[^>]*>/, html) do
      [tag] -> tag
      nil -> ""
    end
  end

  describe "merge_other_params/2" do
    test "substitutes sentinel with free text" do
      params = %{"varv" => "__other__", "varv__other" => "Punane"}
      assert FormBuilder.merge_other_params([@field], params) == %{"varv" => "Punane"}
    end

    test "is a no-op for regular values" do
      params = %{"varv" => "Must", "varv__other" => "ignored"}
      assert FormBuilder.merge_other_params([@field], params) == %{"varv" => "Must"}
    end

    test "checkbox list sentinel is replaced" do
      field = %{@field | "type" => "checkbox"}
      params = %{"varv" => ["Must", "__other__"], "varv__other" => "Punane"}
      assert FormBuilder.merge_other_params([field], params) == %{"varv" => ["Must", "Punane"]}
    end

    test "falls back to empty string when the companion field is missing" do
      params = %{"varv" => "__other__"}
      assert FormBuilder.merge_other_params([@field], params) == %{"varv" => ""}
    end

    test "is idempotent for fields without allow_other — companion key untouched" do
      field = Map.delete(@field, "allow_other")
      params = %{"varv" => "__other__", "varv__other" => "Punane"}
      assert FormBuilder.merge_other_params([field], params) == params
    end

    test "leaves unrelated params untouched" do
      fields = [@field, %{"type" => "text", "key" => "name"}]
      params = %{"varv" => "Must", "name" => "Jaan"}
      assert FormBuilder.merge_other_params(fields, params) == params
    end
  end

  describe "build_field/3 — radio with allow_other" do
    test "renders the Other option and a companion text input" do
      html = FormBuilder.build_field(@field, changeset(%{})) |> rendered_to_string()

      assert html =~ "__other__"
      assert html =~ ~s(name="phoenix_kit_entity_data[data][varv__other]")
    end

    test "checks Other and fills the text input for a stored custom value" do
      html =
        FormBuilder.build_field(@field, changeset(%{"varv" => "Roheline"}))
        |> rendered_to_string()

      assert other_input_tag(html) =~ "checked"
      assert html =~ "Roheline"
    end

    test "does not check Other for a known option" do
      html =
        FormBuilder.build_field(@field, changeset(%{"varv" => "Must"})) |> rendered_to_string()

      refute other_input_tag(html) =~ "checked"
    end

    test "without allow_other, no Other option is rendered" do
      field = Map.delete(@field, "allow_other")
      html = FormBuilder.build_field(field, changeset(%{})) |> rendered_to_string()

      refute html =~ "__other__"
    end
  end

  describe "build_field/3 — select with allow_other" do
    @select_field %{@field | "type" => "select"}

    test "renders the Other option and a companion text input" do
      html = FormBuilder.build_field(@select_field, changeset(%{})) |> rendered_to_string()

      assert html =~ ~s(value="__other__")
      assert html =~ ~s(name="phoenix_kit_entity_data[data][varv__other]")
    end

    test "selects Other and fills the text input for a stored custom value" do
      html =
        FormBuilder.build_field(@select_field, changeset(%{"varv" => "Roheline"}))
        |> rendered_to_string()

      assert html =~ ~s(value="__other__" selected)
      assert html =~ "Roheline"
    end
  end

  describe "build_field/3 — checkbox with allow_other" do
    @checkbox_field %{@field | "type" => "checkbox"}

    test "renders the Other option and a companion text input" do
      html = FormBuilder.build_field(@checkbox_field, changeset(%{})) |> rendered_to_string()

      assert html =~ ~s(value="__other__")
      assert html =~ ~s(name="phoenix_kit_entity_data[data][varv__other]")
    end

    test "checks Other and fills the text input for a stored custom value" do
      html =
        FormBuilder.build_field(@checkbox_field, changeset(%{"varv" => ["Must", "Roheline"]}))
        |> rendered_to_string()

      assert other_input_tag(html) =~ "checked"
      assert html =~ "Roheline"
    end
  end
end
