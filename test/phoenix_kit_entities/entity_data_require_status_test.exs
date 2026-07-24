defmodule PhoenixKitEntities.EntityDataRequireStatusTest do
  @moduledoc """
  `EntityData.update/3` validates its `:require_status` option before
  ever touching the database — this lets the "wrong shape" case be a
  plain, DB-free unit test rather than an integration one.

  DB-backed behavior of `:require_status` (matching/mismatching status,
  the freshly-read-row semantics) is covered in
  `entity_data_extras_test.exs`.
  """
  use ExUnit.Case, async: true

  alias PhoenixKitEntities.EntityData

  describe "require_status validation" do
    test "a bare status string raises a clear ArgumentError instead of a CaseClauseError" do
      record = %EntityData{uuid: Ecto.UUID.generate()}

      assert_raise ArgumentError, ~r/expects a list of statuses/i, fn ->
        EntityData.update(record, %{title: "New"}, require_status: "draft")
      end
    end

    test "the error message names the offending value and shows the fix" do
      record = %EntityData{uuid: Ecto.UUID.generate()}

      error =
        assert_raise ArgumentError, fn ->
          EntityData.update(record, %{title: "New"}, require_status: "draft")
        end

      assert error.message =~ ~s("draft")
      assert error.message =~ ~s(require_status: ["draft"])
    end
  end
end
