defmodule PhoenixKitEntities.ErrorsTest do
  use ExUnit.Case, async: true

  alias PhoenixKitEntities.Errors

  describe "message/1 plain atoms" do
    test ":cannot_remove_primary" do
      assert Errors.message(:cannot_remove_primary) == "Cannot remove the primary language."
    end

    test ":not_multilang" do
      assert Errors.message(:not_multilang) == "Multi-language support is not enabled."
    end

    test ":entity_not_found" do
      assert Errors.message(:entity_not_found) == "Entity not found."
    end

    test ":not_found" do
      assert Errors.message(:not_found) == "Record not found."
    end

    test ":invalid_format" do
      assert Errors.message(:invalid_format) == "Invalid format."
    end

    test ":unexpected" do
      assert Errors.message(:unexpected) == "An unexpected error occurred."
    end
  end

  describe "message/1 tagged tuples" do
    test "{:invalid_field_type, _} interpolates the supplied type" do
      assert Errors.message({:invalid_field_type, "blob"}) == "Invalid field type: blob"
    end

    test "{:requires_options, _} interpolates the supplied type" do
      assert Errors.message({:requires_options, "select"}) ==
               "Field type 'select' requires options"
    end

    test "{:missing_required_keys, _} joins the keys" do
      assert Errors.message({:missing_required_keys, ["key", "label"]}) ==
               "Missing required keys: key, label"
    end

    test "{:user_entity_limit_reached, _} interpolates the limit" do
      assert Errors.message({:user_entity_limit_reached, 100}) ==
               "You have reached the maximum limit of 100 entities"
    end
  end

  describe "message/1 fallback shapes" do
    test "binary passes through unchanged" do
      assert Errors.message("custom legacy message") == "custom legacy message"
    end

    test "unknown atom renders as Unexpected error" do
      assert Errors.message(:totally_unknown) == "Unexpected error: :totally_unknown"
    end

    test "unknown tuple renders as Unexpected error" do
      assert Errors.message({:weird, :shape, 42}) == "Unexpected error: {:weird, :shape, 42}"
    end

    test "struct renders as Unexpected error" do
      assert Errors.message(%{some: :map}) == "Unexpected error: %{some: :map}"
    end
  end
end
