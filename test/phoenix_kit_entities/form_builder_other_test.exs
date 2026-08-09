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

  defp entity(fields), do: %PhoenixKitEntities{fields_definition: fields}

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

    test "an Other checkbox ticked with no text typed doesn't leave a blank entry" do
      field = %{@field | "type" => "checkbox"}
      params = %{"varv" => ["Must", "__other__"], "varv__other" => ""}
      assert FormBuilder.merge_other_params([field], params) == %{"varv" => ["Must"]}
    end

    test "an Other checkbox ticked with a missing companion field doesn't leave a blank entry" do
      field = %{@field | "type" => "checkbox"}
      params = %{"varv" => ["Must", "__other__"]}
      assert FormBuilder.merge_other_params([field], params) == %{"varv" => ["Must"]}
    end
  end

  # The admin field-definition builder (entity_form.ex) submits the toggle
  # as an HTML checkbox — the value that actually lands in the persisted
  # `fields_definition` JSONB is the string "true", never the Elixir
  # boolean. Every consumer must treat both as equivalent; these mirror the
  # `@field`-based tests above but with the flag exactly as the UI stores it.
  describe "allow_other as the UI actually stores it (string \"true\", not boolean)" do
    @string_field %{@field | "allow_other" => "true"}

    test "merge_other_params resolves the sentinel" do
      params = %{"varv" => "__other__", "varv__other" => "Punane"}
      assert FormBuilder.merge_other_params([@string_field], params) == %{"varv" => "Punane"}
    end

    test "build_field renders the Other option" do
      html = FormBuilder.build_field(@string_field, changeset(%{})) |> rendered_to_string()
      assert html =~ "__other__"
    end

    test "validate_data accepts a custom value" do
      fields = [@string_field]
      merged = FormBuilder.merge_other_params(fields, %{"varv" => "Roheline"})
      assert {:ok, %{"varv" => "Roheline"}} = FormBuilder.validate_data(entity(fields), merged)
    end
  end

  describe "validate_data/2 — end-to-end through merge_other_params" do
    # This is the exact pipeline do_validate/do_save (data_form.ex) and
    # handle_submission (entity_form_controller.ex) run in production:
    # raw submitted params -> merge_other_params -> validate_data. Confirms
    # the loosened validate_type clause (form_builder.ex) only kicks in
    # when allow_other is actually set — a field without it keeps the
    # strict options check.
    test "a custom value survives validation for an allow_other field" do
      fields = [@field]
      raw_params = %{"varv" => "__other__", "varv__other" => "Punane"}
      merged = FormBuilder.merge_other_params(fields, raw_params)

      assert {:ok, %{"varv" => "Punane"}} = FormBuilder.validate_data(entity(fields), merged)
    end

    test "the same raw sentinel is rejected when the field lacks allow_other" do
      field = Map.delete(@field, "allow_other")
      fields = [field]
      raw_params = %{"varv" => "__other__", "varv__other" => "Punane"}

      # merge_other_params is a no-op here (no allow_other), so the literal
      # sentinel reaches validate_data unresolved and must fail options
      # validation just like any other value outside the fixed list.
      merged = FormBuilder.merge_other_params(fields, raw_params)
      assert merged == raw_params

      assert {:error, %{"varv" => _}} = FormBuilder.validate_data(entity(fields), merged)
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
