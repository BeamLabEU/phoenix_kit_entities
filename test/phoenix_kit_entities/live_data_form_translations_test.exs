defmodule PhoenixKitEntities.LiveDataFormTranslationsTest do
  @moduledoc """
  `PhoenixKitEntities.Components.LiveDataForm`'s `:readonly` render resolves
  field-level `"translations"` (see `PhoenixKitEntities.FormBuilder`'s
  moduledoc for the display-only contract) directly via
  `FormBuilder.translated_label/2` / `translated_option_label/3`, driven by
  the component's `lang` attribute — this path never touches
  `FormBuilder.build_fields/3`, so (unlike the `:edit`-mode "lang
  pass-through" test in `live_data_form_test.exs`) it never probes
  `Multilang`/`Languages` and stays DB-free regardless of `lang`.

  `:edit` mode gets the same label/option translation "for free" through
  `FormBuilder.build_fields/3` — already unit-tested directly (no DB
  dependency) in `form_builder_translations_test.exs` — so it isn't
  re-tested here.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixKitEntities.Components.LiveDataForm
  alias PhoenixKitEntities.EntityData

  @endpoint PhoenixKitEntities.Test.Endpoint

  @color_field %{
    "type" => "radio",
    "key" => "color",
    "label" => "Värv",
    "options" => ["Must", "Valge"],
    "allow_other" => true,
    "translations" => %{
      "ru" => %{"label" => "Цвет", "options" => %{"Must" => "Чёрный", "Valge" => "Белый"}}
    }
  }

  @heading_field %{
    "type" => "heading",
    "key" => "sec",
    "label" => "Varustus",
    "translations" => %{"ru" => %{"label" => "Варочная panel"}}
  }

  defp entity(fields) do
    %PhoenixKitEntities{uuid: Ecto.UUID.generate(), fields_definition: fields}
  end

  defp record(entity, data \\ %{}) do
    %EntityData{
      uuid: Ecto.UUID.generate(),
      entity_uuid: entity.uuid,
      entity: entity,
      title: "Survey",
      status: "published",
      data: data
    }
  end

  defp render_form(assigns) do
    render_component(
      LiveDataForm,
      Map.put(assigns, :id, "live-data-form-#{System.unique_integer([:positive])}")
    )
  end

  describe ":readonly mode — translated label + option" do
    test "the stored canonical value renders its translation for lang" do
      e = entity([@color_field])
      r = record(e, %{"color" => "Must"})

      html = render_form(%{record: r, mode: :readonly, lang: "ru", actor: nil, submit_label: nil})

      assert html =~ "Цвет"
      assert html =~ "Чёрный"
      refute html =~ "Värv"
      refute html =~ "Must"
    end

    test "falls back to the original label/option without lang" do
      e = entity([@color_field])
      r = record(e, %{"color" => "Must"})

      html = render_form(%{record: r, mode: :readonly, lang: nil, actor: nil, submit_label: nil})

      assert html =~ "Värv"
      assert html =~ "Must"
      refute html =~ "Цвет"
      refute html =~ "Чёрный"
    end

    test "an allow_other free-text value (outside options) renders as-is, untranslated" do
      e = entity([@color_field])
      r = record(e, %{"color" => "Crimson"})

      html = render_form(%{record: r, mode: :readonly, lang: "ru", actor: nil, submit_label: nil})

      assert html =~ "Crimson"
    end

    test "a select field's stored value is translated the same way as radio" do
      field = %{@color_field | "type" => "select"}
      e = entity([field])
      r = record(e, %{"color" => "Valge"})

      html = render_form(%{record: r, mode: :readonly, lang: "ru", actor: nil, submit_label: nil})

      assert html =~ "Белый"
      refute html =~ "Valge"
    end

    test "a checkbox list translates each stored value before joining" do
      field = %{@color_field | "type" => "checkbox"}
      e = entity([field])
      r = record(e, %{"color" => ["Must", "Valge"]})

      html = render_form(%{record: r, mode: :readonly, lang: "ru", actor: nil, submit_label: nil})

      assert html =~ "Чёрный, Белый"
    end

    test "an empty/nil stored value still renders the dash placeholder" do
      e = entity([@color_field])
      r = record(e, %{})

      html = render_form(%{record: r, mode: :readonly, lang: "ru", actor: nil, submit_label: nil})

      assert html =~ "—"
    end

    test "a heading is translated the same way as a regular field label" do
      e = entity([@heading_field])
      r = record(e)

      html = render_form(%{record: r, mode: :readonly, lang: "ru", actor: nil, submit_label: nil})

      assert html =~ "Варочная panel"
      refute html =~ "Varustus"
    end
  end
end
