defmodule PhoenixKitEntities.EntityDataChangesetTest do
  use PhoenixKitEntities.DataCase, async: true

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "data_cs_test",
          display_name: "Data CS Test",
          display_name_plural: "Data CS Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"}
          ],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, actor_uuid: actor_uuid}
  end

  defp valid_attrs(ctx) do
    %{
      entity_uuid: ctx.entity.uuid,
      title: "Test Record",
      created_by_uuid: ctx.actor_uuid
    }
  end

  defp changeset(ctx, attrs \\ %{}) do
    EntityData.changeset(%EntityData{}, Map.merge(valid_attrs(ctx), attrs))
  end

  describe "required fields" do
    test "valid with required fields", ctx do
      cs = changeset(ctx)
      refute errors_on(cs)[:title]
      refute errors_on(cs)[:entity_uuid]
    end

    test "invalid without title", ctx do
      cs = changeset(ctx, %{title: nil})
      assert errors_on(cs)[:title]
    end

    test "invalid without entity_uuid", ctx do
      cs = changeset(ctx, %{entity_uuid: nil})
      assert errors_on(cs)[:entity_uuid]
    end
  end

  describe "title validation" do
    test "valid title", ctx do
      cs = changeset(ctx, %{title: "My Record"})
      refute errors_on(cs)[:title]
    end

    test "invalid - empty string", ctx do
      cs = changeset(ctx, %{title: ""})
      assert errors_on(cs)[:title]
    end

    test "invalid - too long (256 chars)", ctx do
      cs = changeset(ctx, %{title: String.duplicate("x", 256)})
      assert errors_on(cs)[:title]
    end

    test "valid - max length (255 chars)", ctx do
      cs = changeset(ctx, %{title: String.duplicate("x", 255)})
      refute errors_on(cs)[:title]
    end
  end

  describe "slug validation" do
    test "valid slug", ctx do
      cs = changeset(ctx, %{slug: "my-record"})
      refute errors_on(cs)[:slug]
    end

    test "valid slug with numbers", ctx do
      cs = changeset(ctx, %{slug: "record-123"})
      refute errors_on(cs)[:slug]
    end

    test "nil slug is valid (optional)", ctx do
      cs = changeset(ctx, %{slug: nil})
      refute errors_on(cs)[:slug]
    end

    test "empty slug is valid", ctx do
      cs = changeset(ctx, %{slug: ""})
      refute errors_on(cs)[:slug]
    end

    test "invalid - uppercase letters", ctx do
      cs = changeset(ctx, %{slug: "My-Record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - spaces", ctx do
      cs = changeset(ctx, %{slug: "my record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - underscores", ctx do
      cs = changeset(ctx, %{slug: "my_record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - double hyphens", ctx do
      cs = changeset(ctx, %{slug: "my--record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - starts with hyphen", ctx do
      cs = changeset(ctx, %{slug: "-record"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - ends with hyphen", ctx do
      cs = changeset(ctx, %{slug: "record-"})
      assert errors_on(cs)[:slug]
    end

    test "invalid - too long (256 chars)", ctx do
      cs = changeset(ctx, %{slug: String.duplicate("a", 256)})
      assert errors_on(cs)[:slug]
    end
  end

  describe "status validation" do
    test "valid - draft", ctx do
      cs = changeset(ctx, %{status: "draft"})
      refute errors_on(cs)[:status]
    end

    test "valid - published", ctx do
      cs = changeset(ctx, %{status: "published"})
      refute errors_on(cs)[:status]
    end

    test "valid - archived", ctx do
      cs = changeset(ctx, %{status: "archived"})
      refute errors_on(cs)[:status]
    end

    test "invalid status", ctx do
      cs = changeset(ctx, %{status: "deleted"})
      assert errors_on(cs)[:status]
    end
  end

  describe "data and metadata" do
    test "accepts map data", ctx do
      cs = changeset(ctx, %{data: %{"name" => "Test", "price" => 10}})
      assert Ecto.Changeset.get_field(cs, :data) == %{"name" => "Test", "price" => 10}
    end

    test "accepts map metadata", ctx do
      cs = changeset(ctx, %{metadata: %{"tags" => ["featured"]}})
      assert Ecto.Changeset.get_field(cs, :metadata) == %{"tags" => ["featured"]}
    end

    test "accepts nil metadata", ctx do
      cs = changeset(ctx, %{metadata: nil})
      refute errors_on(cs)[:metadata]
    end
  end

  describe "position" do
    test "accepts integer position", ctx do
      cs = changeset(ctx, %{position: 5})
      assert Ecto.Changeset.get_field(cs, :position) == 5
    end

    test "accepts nil position", ctx do
      cs = changeset(ctx, %{position: nil})
      refute errors_on(cs)[:position]
    end
  end
end
