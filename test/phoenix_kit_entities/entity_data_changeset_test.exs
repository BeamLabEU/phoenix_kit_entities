defmodule PhoenixKitEntities.EntityDataChangesetTest do
  use ExUnit.Case

  alias PhoenixKitEntities.EntityData

  @valid_attrs %{
    entity_uuid: "01912345-6789-7abc-def0-123456789abc",
    title: "Test Record",
    created_by_uuid: "01912345-6789-7abc-def0-abcdef123456"
  }

  defp changeset(attrs \\ %{}) do
    EntityData.changeset(%EntityData{}, Map.merge(@valid_attrs, attrs))
  end

  describe "required fields" do
    test "valid with required fields" do
      cs = changeset()
      # May have errors from validate_data_against_entity (DB lookup) but
      # basic validation should pass
      refute errors_on(cs)[:title]
      refute errors_on(cs)[:entity_uuid]
    end

    test "invalid without title" do
      cs = changeset(%{title: nil})
      assert errors_on(cs)[:title]
    end

    test "invalid without entity_uuid" do
      cs = changeset(%{entity_uuid: nil})
      assert errors_on(cs)[:entity_uuid]
    end
  end

  describe "title validation" do
    test "valid title" do
      cs = changeset(%{title: "My Record"})
      refute errors_on(cs)[:title]
    end

    test "invalid - empty string" do
      cs = changeset(%{title: ""})
      assert errors_on(cs)[:title]
    end

    test "invalid - too long (256 chars)" do
      cs = changeset(%{title: String.duplicate("x", 256)})
      assert errors_on(cs)[:title]
    end

    test "valid - max length (255 chars)" do
      cs = changeset(%{title: String.duplicate("x", 255)})
      refute errors_on(cs)[:title]
    end
  end

  describe "slug validation" do
    test "valid slug" do
      cs = changeset(%{slug: "my-record"})
      refute errors_on(cs)[:slug]
    end

    test "valid slug with numbers" do
      cs = changeset(%{slug: "record-123"})
      refute errors_on(cs)[:slug]
    end

    test "nil slug is valid (optional)" do
      cs = changeset(%{slug: nil})
      refute errors_on(cs)[:slug]
    end

    test "empty slug is valid" do
      cs = changeset(%{slug: ""})
      refute errors_on(cs)[:slug]
    end

    test "invalid - uppercase letters" do
      cs = changeset(%{slug: "My-Record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - spaces" do
      cs = changeset(%{slug: "my record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - underscores" do
      cs = changeset(%{slug: "my_record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - double hyphens" do
      cs = changeset(%{slug: "my--record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - starts with hyphen" do
      cs = changeset(%{slug: "-record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - ends with hyphen" do
      cs = changeset(%{slug: "record-"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - too long (256 chars)" do
      cs = changeset(%{slug: String.duplicate("a", 256)})
      assert errors_on(cs)[:slug]
    end
  end

  describe "status validation" do
    test "valid - draft" do
      cs = changeset(%{status: "draft"})
      refute errors_on(cs)[:status]
    end

    test "valid - published" do
      cs = changeset(%{status: "published"})
      refute errors_on(cs)[:status]
    end

    test "valid - archived" do
      cs = changeset(%{status: "archived"})
      refute errors_on(cs)[:status]
    end

    test "invalid status" do
      cs = changeset(%{status: "deleted"})
      assert errors_on(cs)[:status]
    end
  end

  describe "data and metadata" do
    test "accepts map data" do
      cs = changeset(%{data: %{"name" => "Test", "price" => 10}})
      assert Ecto.Changeset.get_field(cs, :data) == %{"name" => "Test", "price" => 10}
    end

    test "accepts map metadata" do
      cs = changeset(%{metadata: %{"tags" => ["featured"]}})
      assert Ecto.Changeset.get_field(cs, :metadata) == %{"tags" => ["featured"]}
    end

    test "accepts nil metadata" do
      cs = changeset(%{metadata: nil})
      refute errors_on(cs)[:metadata]
    end
  end

  describe "position" do
    test "accepts integer position" do
      cs = changeset(%{position: 5})
      assert Ecto.Changeset.get_field(cs, :position) == 5
    end

    test "accepts nil position" do
      cs = changeset(%{position: nil})
      refute errors_on(cs)[:position]
    end
  end

  # Helper to extract error messages from a changeset
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
