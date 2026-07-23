defmodule PhoenixKitEntities.FieldTypesHeadingTest do
  @moduledoc """
  `"heading"` is a display-only field type: a section heading rendered in
  the entity form with no associated input and no stored data. No DB
  needed — `FieldTypes` is pure config/lookup.
  """
  use ExUnit.Case, async: true
  alias PhoenixKitEntities.FieldTypes

  test "heading is a registered field type without options" do
    assert FieldTypes.valid_type?("heading")
    type = FieldTypes.get_type("heading")
    refute type.requires_options
    assert type.category == :basic
  end

  test "validate_field accepts heading without options" do
    field = %{"type" => "heading", "key" => "sec_ahi", "label" => "Ahi"}
    assert {:ok, _} = FieldTypes.validate_field(field)
  end

  test "heading exposes an icon and empty default props" do
    type = FieldTypes.get_type("heading")
    assert type.icon == "hero-bars-3-bottom-left"
    assert type.default_props == %{}
  end

  test "heading appears in the field picker" do
    picker_entry = Enum.find(FieldTypes.for_picker(), &(&1.value == "heading"))
    refute is_nil(picker_entry)
    assert picker_entry.requires_options == false
  end

  test "description_for/1 returns a translated description" do
    assert FieldTypes.description_for("heading") == "Display-only section heading (no data)"
  end
end
