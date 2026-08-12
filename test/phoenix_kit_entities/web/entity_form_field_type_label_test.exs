defmodule PhoenixKitEntities.Web.EntityFormFieldTypeLabelTest do
  @moduledoc """
  Regression guard for `EntityForm.field_type_label/1`.

  Before this test existed, the function carried its own 13 literal
  `gettext(...)` clauses (one per known field type) plus a catch-all that
  duplicated `FieldTypes.label_for/1` — a third source of truth, with the
  catch-all's `_type_info -> FieldTypes.label_for(type_name)` branch
  unreachable because every one of the 13 map keys was already caught above
  it. `field_type_label/1` now simply delegates to `FieldTypes.label_for/1`.
  Plain function calls only — no LiveView mount needed, so this runs
  without a database.
  """

  use ExUnit.Case, async: true

  alias PhoenixKitEntities.FieldTypes
  alias PhoenixKitEntities.Web.EntityForm

  test "delegates to FieldTypes.label_for/1 for every known field type" do
    for type_name <- FieldTypes.list_types() do
      assert EntityForm.field_type_label(type_name) == FieldTypes.label_for(type_name),
             "field_type_label(#{inspect(type_name)}) diverged from FieldTypes.label_for/1"
    end
  end

  test "falls back to the raw type name for an unknown type, same as FieldTypes.label_for/1" do
    assert EntityForm.field_type_label("not_a_real_type") == "not_a_real_type"

    assert EntityForm.field_type_label("not_a_real_type") ==
             FieldTypes.label_for("not_a_real_type")
  end
end
