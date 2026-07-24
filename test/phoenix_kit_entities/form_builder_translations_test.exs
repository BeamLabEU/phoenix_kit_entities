defmodule PhoenixKitEntities.FormBuilderTranslationsTest do
  @moduledoc """
  Unit tests (DB-free — pure functions + `~H` rendering, no changeset
  validation touches the database) for `PhoenixKitEntities.FormBuilder`'s
  field-level `"translations"` contract: `translated_label/2` and
  `translated_option_label/3`, plus their effect on `build_field/3`'s
  rendered HTML.

  Display-only throughout: the canonical `field["label"]` / option
  strings and whatever `validate_data/3` stores are never touched by a
  `"translations"` key — only what gets rendered changes. See
  `FormBuilder`'s moduledoc for the full contract.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.FormBuilder

  @field %{
    "type" => "radio",
    "key" => "color",
    "label" => "Värv",
    "options" => ["Must", "Valge"],
    "translations" => %{
      "ru" => %{"label" => "Цвет", "options" => %{"Must" => "Чёрный", "Valge" => "Белый"}},
      "en" => %{"label" => "Colour", "options" => %{"Must" => "Black", "Valge" => "White"}}
    }
  }

  defp changeset(data \\ %{}), do: Ecto.Changeset.cast(%EntityData{data: data}, %{}, [])

  describe "translated_label/2" do
    test "returns the translation for an exact language match" do
      assert FormBuilder.translated_label(@field, "ru") == "Цвет"
    end

    test "falls back to the original label when lang_code is nil" do
      assert FormBuilder.translated_label(@field, nil) == "Värv"
    end

    test "falls back to the original label when the language isn't present" do
      assert FormBuilder.translated_label(@field, "et") == "Värv"
    end

    test "falls back to the original label when the field has no translations key at all" do
      field = Map.delete(@field, "translations")
      assert FormBuilder.translated_label(field, "ru") == "Värv"
    end

    test "falls back when the translation entry has a blank label" do
      field = put_in(@field, ["translations", "ru", "label"], "")
      assert FormBuilder.translated_label(field, "ru") == "Värv"
    end

    test "tolerates a base-code lookup when stored under a dialect code" do
      field = %{"label" => "Värv", "translations" => %{"ru-RU" => %{"label" => "Цвет (RU)"}}}
      assert FormBuilder.translated_label(field, "ru") == "Цвет (RU)"
    end

    test "tolerates a dialect-code lookup when stored under the base code" do
      assert FormBuilder.translated_label(@field, "ru-RU") == "Цвет"
    end

    test "works for heading-style fields (label only, no options)" do
      field = %{"label" => "Varv", "translations" => %{"ru" => %{"label" => "Секция"}}}
      assert FormBuilder.translated_label(field, "ru") == "Секция"
    end
  end

  describe "translated_option_label/3" do
    test "returns the translated option for an exact language match" do
      assert FormBuilder.translated_option_label(@field, "Must", "ru") == "Чёрный"
    end

    test "falls back to the canonical option string when lang_code is nil" do
      assert FormBuilder.translated_option_label(@field, "Must", nil) == "Must"
    end

    test "falls back when the language isn't present" do
      assert FormBuilder.translated_option_label(@field, "Must", "et") == "Must"
    end

    test "falls back when the field has no translations key at all" do
      field = Map.delete(@field, "translations")
      assert FormBuilder.translated_option_label(field, "Must", "ru") == "Must"
    end

    test "falls back when this specific option has no translated entry (allow_other free text)" do
      assert FormBuilder.translated_option_label(@field, "Crimson", "ru") == "Crimson"
    end

    test "tolerates a dialect-code lookup when stored under the base code" do
      assert FormBuilder.translated_option_label(@field, "Must", "ru-RU") == "Чёрный"
    end

    test "falls back, without raising, when \"options\" is a list instead of a map" do
      field = %{"translations" => %{"ru" => %{"options" => ["Must"]}}}
      assert FormBuilder.translated_option_label(field, "Must", "ru") == "Must"
    end

    test "falls back, without raising, when \"options\" is a string instead of a map" do
      field = %{"translations" => %{"ru" => %{"options" => "x"}}}
      assert FormBuilder.translated_option_label(field, "Must", "ru") == "Must"
    end

    test "falls back when this option's translated entry is a blank string" do
      field = %{"translations" => %{"ru" => %{"options" => %{"Must" => ""}}}}
      assert FormBuilder.translated_option_label(field, "Must", "ru") == "Must"
    end

    test "falls back when \"translations\" itself isn't a map" do
      field = %{"translations" => "not-a-map"}
      assert FormBuilder.translated_option_label(field, "Must", "ru") == "Must"
    end

    test "falls back when the language entry isn't a map" do
      field = %{"translations" => %{"ru" => "Цвет"}}
      assert FormBuilder.translated_option_label(field, "Must", "ru") == "Must"
    end
  end

  describe "build_field/3 — label translation in rendered HTML" do
    test "radio label is translated when lang_code is passed" do
      html = FormBuilder.build_field(@field, changeset(), lang_code: "ru") |> rendered_to_string()

      assert html =~ "Цвет"
      refute html =~ "Värv"
    end

    test "regression: no lang_code renders the original label, never the translation" do
      html = FormBuilder.build_field(@field, changeset()) |> rendered_to_string()

      assert html =~ "Värv"
      refute html =~ "Цвет"
    end
  end

  describe "build_field/3 — option translation in rendered HTML (value stays canonical)" do
    test "radio: option text translated, input value canonical" do
      html =
        FormBuilder.build_field(@field, changeset(%{"color" => "Must"}), lang_code: "ru")
        |> rendered_to_string()

      assert html =~ "Чёрный"
      assert html =~ "Белый"
      assert html =~ ~s(value="Must")
      assert html =~ ~s(value="Valge")
      refute html =~ ~s(value="Чёрный")
    end

    test "select: option text translated, option value canonical" do
      field = %{@field | "type" => "select"}

      html =
        FormBuilder.build_field(field, changeset(%{"color" => "Must"}), lang_code: "ru")
        |> rendered_to_string()

      assert html =~ ~s(value="Must")
      assert html =~ "Чёрный"
      refute html =~ ~s(value="Чёрный")
    end

    test "checkbox: option text translated, input value canonical" do
      field = %{@field | "type" => "checkbox"}

      html =
        FormBuilder.build_field(field, changeset(%{"color" => ["Must"]}), lang_code: "ru")
        |> rendered_to_string()

      assert html =~ "Чёрный"
      assert html =~ ~s(value="Must")
    end

    test "the synthetic 'Other' option is untouched (stays gettext, not looked up in translations)" do
      field = Map.put(@field, "allow_other", true)

      html =
        FormBuilder.build_field(field, changeset(), lang_code: "ru") |> rendered_to_string()

      assert html =~ "Other"
    end

    test "regression: no lang_code never leaks translated option text" do
      html =
        FormBuilder.build_field(@field, changeset(%{"color" => "Must"})) |> rendered_to_string()

      refute html =~ "Чёрный"
      refute html =~ "Белый"
      assert html =~ ~s(value="Must")
      assert html =~ ~s(value="Valge")
    end
  end

  describe "build_field/3 — heading translation" do
    @heading_field %{
      "type" => "heading",
      "key" => "sec",
      "label" => "Varv",
      "translations" => %{"ru" => %{"label" => "Секция"}}
    }

    test "heading label is translated when lang_code is passed" do
      html =
        FormBuilder.build_field(@heading_field, changeset(), lang_code: "ru")
        |> rendered_to_string()

      assert html =~ "Секция"
      refute html =~ "Varv"
    end

    test "regression: heading without lang_code renders the original label" do
      html = FormBuilder.build_field(@heading_field, changeset()) |> rendered_to_string()

      assert html =~ "Varv"
    end
  end

  describe "translations are inert for validation/param-merging" do
    test "validate_data stores the canonical value, never a translated one" do
      entity = %PhoenixKitEntities{fields_definition: [@field]}

      assert {:ok, %{"color" => "Must"}} =
               FormBuilder.validate_data(entity, %{"color" => "Must"})
    end

    test "merge_other_params is unaffected by a translations key" do
      params = %{"color" => "Must"}
      assert FormBuilder.merge_other_params([@field], params) == params
    end
  end
end
