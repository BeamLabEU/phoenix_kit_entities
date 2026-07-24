defmodule PhoenixKitEntities.FormBuilderHeadingTest do
  @moduledoc """
  `"heading"` fields are display-only: `build_field/3` renders a section
  heading with no input, and `validate_data/3` never stores or requires
  a value for them. Both functions are pure — no DB needed.
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixKitEntities.FormBuilder

  defp entity(fields), do: %PhoenixKitEntities{fields_definition: fields}

  describe "build_field/3" do
    test "renders a heading with the label and no input" do
      field = %{"type" => "heading", "key" => "sec_ahi", "label" => "Ahi"}
      changeset = Ecto.Changeset.cast(%PhoenixKitEntities.EntityData{data: %{}}, %{}, [])

      html = FormBuilder.build_field(field, changeset) |> rendered_to_string()

      assert html =~ "<h3"
      assert html =~ "Ahi"
      refute html =~ "<input"
    end
  end

  describe "validate_data/3" do
    test "skips heading fields entirely — no key, no error" do
      fields = [
        %{"type" => "heading", "key" => "sec_ahi", "label" => "Ahi"},
        %{"type" => "text", "key" => "name", "label" => "Name", "required" => true}
      ]

      assert {:ok, data} = FormBuilder.validate_data(entity(fields), %{"name" => "value"})
      refute Map.has_key?(data, "sec_ahi")
      assert data == %{"name" => "value"}
    end

    test "a heading field never triggers a required error" do
      fields = [%{"type" => "heading", "key" => "sec_ahi", "label" => "Ahi", "required" => true}]

      assert {:ok, data} = FormBuilder.validate_data(entity(fields), %{})
      assert data == %{}
    end
  end
end
