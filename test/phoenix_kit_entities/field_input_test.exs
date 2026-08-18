defmodule PhoenixKitEntities.Components.FieldInputTest do
  @moduledoc """
  The embeddable inline field renderer + its casting counterpart
  (`FormBuilder.cast_field/2`) — the contract hosts like the catalogue's
  attribute-set editor build on. Pure render/cast pins, no DB.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias PhoenixKitEntities.FormBuilder

  defp render_input(field, extra \\ []) do
    assigns =
      Map.merge(
        %{field: field, name: "extras[#{field["key"]}]", value: extra[:value]},
        Map.new(Keyword.delete(extra, :value))
      )

    render_component(
      fn assigns ->
        ~H"""
        <PhoenixKitEntities.Components.FieldInput.field_input
          field={@field}
          name={@name}
          value={@value}
          size={assigns[:size] || "sm"}
          on_pick={assigns[:on_pick]}
          on_clear={assigns[:on_clear]}
          pick_params={assigns[:pick_params] || %{}}
        />
        """
      end,
      assigns
    )
  end

  describe "field_input/1 rendering" do
    test "typed inputs debounce on blur" do
      for type <- ~w(text email url number date) do
        html = render_input(%{"type" => type, "key" => "k", "label" => "K"}, value: nil)
        assert html =~ ~s(phx-debounce="blur")
        assert html =~ ~s(name="extras[k]")
      end

      html = render_input(%{"type" => "textarea", "key" => "k", "label" => "K"})
      assert html =~ ~s(phx-debounce="blur")
    end

    test "boolean pairs the toggle with a hidden false" do
      html = render_input(%{"type" => "boolean", "key" => "wet", "label" => "Wet"}, value: true)
      assert html =~ ~s(type="hidden" name="extras[wet]" value="false")
      assert html =~ "checked"
      assert html =~ "toggle"
    end

    test "select renders options with the current one selected" do
      field = %{
        "type" => "select",
        "key" => "fin",
        "label" => "F",
        "options" => ["Matte", "Gloss"]
      }

      html = render_input(field, value: "Gloss")
      assert html =~ ~s(<option value="Gloss" selected>)
      assert html =~ ~s(<option value="Matte">)
    end

    test "checkbox group keeps the key present via hidden input" do
      field = %{"type" => "checkbox", "key" => "tags", "label" => "T", "options" => ["a", "b"]}
      html = render_input(field, value: ["b"])
      assert html =~ ~s(type="hidden" name="extras[tags]" value="")
      assert html =~ ~s(name="extras[tags][]")
      assert html =~ "checked"
    end

    test "image renders thumbnail + Change/Clear wired to host events" do
      uuid = Ecto.UUID.generate()

      field = %{"type" => "image", "key" => "swatch", "label" => "Swatch"}

      html =
        render_input(field,
          value: uuid,
          on_pick: "pick_media",
          on_clear: "clear_media",
          pick_params: %{"uuid" => "row-1"}
        )

      assert html =~ "<img"
      assert html =~ ~s(phx-click="pick_media")
      assert html =~ ~s(phx-value-field="swatch")
      assert html =~ ~s(phx-value-uuid="row-1")
      assert html =~ ~s(phx-click="clear_media")
      assert html =~ "Change"

      # No value → Choose, no thumbnail, no Clear.
      empty = render_input(field, on_pick: "pick_media", on_clear: "clear_media")
      refute empty =~ "<img"
      assert empty =~ "Choose"
      refute empty =~ ~s(phx-click="clear_media")
    end

    test "heading renders nothing; unknown types degrade to a note" do
      assert render_input(%{"type" => "heading", "key" => "h", "label" => "H"}) =~ ~r/^\s*$/

      html = render_input(%{"type" => "relation", "key" => "r", "label" => "R"})
      assert html =~ "Unsupported field type"
    end
  end

  describe "FormBuilder.cast_field/2" do
    test "coerces per type, blank clears, required still enforced" do
      assert {:ok, 12.5} = FormBuilder.cast_field(%{"type" => "number", "key" => "p"}, "12.5")
      assert {:error, _} = FormBuilder.cast_field(%{"type" => "number", "key" => "p"}, "12abc")
      assert {:ok, nil} = FormBuilder.cast_field(%{"type" => "number", "key" => "p"}, "")

      assert {:ok, true} = FormBuilder.cast_field(%{"type" => "boolean", "key" => "b"}, "true")
      assert {:ok, false} = FormBuilder.cast_field(%{"type" => "boolean", "key" => "b"}, "false")

      select = %{"type" => "select", "key" => "s", "options" => ["A", "B"]}
      assert {:ok, "A"} = FormBuilder.cast_field(select, "A")
      assert {:error, _} = FormBuilder.cast_field(select, "C")

      checkbox = %{"type" => "checkbox", "key" => "c", "options" => ["a", "b"]}
      assert {:ok, ["a"]} = FormBuilder.cast_field(checkbox, ["a"])
      assert {:ok, []} = FormBuilder.cast_field(checkbox, "")

      assert {:error, _} =
               FormBuilder.cast_field(%{"type" => "text", "key" => "t", "required" => true}, "")
    end

    test "media references accept storage uuids only" do
      uuid = Ecto.UUID.generate()
      image = %{"type" => "image", "key" => "i"}

      assert {:ok, ^uuid} = FormBuilder.cast_field(image, uuid)
      assert {:ok, nil} = FormBuilder.cast_field(image, "")
      assert {:error, _} = FormBuilder.cast_field(image, "not-a-uuid")
      assert {:error, _} = FormBuilder.cast_field(%{"type" => "video", "key" => "v"}, "nope")
    end
  end
end
