defmodule PhoenixKitEntities.ActivityLoggingTest do
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor_uuid = Ecto.UUID.generate()
    other_actor = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "log_test",
          display_name: "Log Test",
          display_name_plural: "Log Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"}
          ],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, actor_uuid: actor_uuid, other_actor: other_actor}
  end

  describe "entity.* actions" do
    test "create_entity logs entity.created with actor + name metadata", ctx do
      assert_activity_logged("entity.created",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: ctx.entity.uuid,
        metadata_has: %{"name" => "log_test", "status" => "published"}
      )
    end

    test "update_entity logs entity.updated with the *current* actor (not the creator)", ctx do
      {:ok, _updated} =
        Entities.update_entity(ctx.entity, %{display_name: "Renamed"},
          actor_uuid: ctx.other_actor
        )

      assert_activity_logged("entity.updated",
        actor_uuid: ctx.other_actor,
        resource_uuid: ctx.entity.uuid
      )
    end

    test "delete_entity logs entity.deleted with the actor", ctx do
      {:ok, _} = Entities.delete_entity(ctx.entity, actor_uuid: ctx.other_actor)

      assert_activity_logged("entity.deleted",
        actor_uuid: ctx.other_actor,
        resource_uuid: ctx.entity.uuid
      )
    end

    test "update_entity {:error, _} logs entity.updated with db_pending: true", ctx do
      {:error, _changeset} =
        Entities.update_entity(ctx.entity, %{name: ""}, actor_uuid: ctx.actor_uuid)

      assert_activity_logged("entity.updated",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"db_pending" => true}
      )
    end
  end

  describe "entity_data.* actions" do
    test "create + update + delete each log with the threaded actor_uuid", ctx do
      {:ok, record} =
        EntityData.create(
          %{
            entity_uuid: ctx.entity.uuid,
            title: "Item",
            slug: "item",
            data: %{"name" => "Acme"},
            created_by_uuid: ctx.actor_uuid
          },
          actor_uuid: ctx.actor_uuid
        )

      assert_activity_logged("entity_data.created",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: record.uuid,
        metadata_has: %{"slug" => "item", "title" => "Item"}
      )

      {:ok, _} =
        EntityData.update(record, %{title: "Renamed"}, actor_uuid: ctx.other_actor)

      assert_activity_logged("entity_data.updated",
        actor_uuid: ctx.other_actor,
        resource_uuid: record.uuid
      )

      {:ok, _} = EntityData.delete(record, actor_uuid: ctx.other_actor)

      assert_activity_logged("entity_data.deleted",
        actor_uuid: ctx.other_actor,
        resource_uuid: record.uuid
      )
    end

    test "create {:error, _} logs entity_data.created with db_pending: true", ctx do
      {:error, _} =
        EntityData.create(
          %{entity_uuid: ctx.entity.uuid, title: "", created_by_uuid: ctx.actor_uuid},
          actor_uuid: ctx.actor_uuid
        )

      assert_activity_logged("entity_data.created",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"db_pending" => true}
      )
    end
  end

  describe "entity_data.bulk_*" do
    test "bulk_update_status emits one summary row, not per-record", ctx do
      uuids =
        for n <- 1..3 do
          {:ok, r} =
            EntityData.create(
              %{
                entity_uuid: ctx.entity.uuid,
                title: "Item #{n}",
                slug: "item-#{n}",
                created_by_uuid: ctx.actor_uuid
              },
              actor_uuid: ctx.actor_uuid
            )

          r.uuid
        end

      {3, _} = EntityData.bulk_update_status(uuids, "archived", actor_uuid: ctx.other_actor)

      assert_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.other_actor,
        metadata_has: %{"status" => "archived", "count" => 3, "uuid_count" => 3}
      )
    end

    test "bulk_delete emits one summary row carrying the count", ctx do
      uuids =
        for n <- 1..2 do
          {:ok, r} =
            EntityData.create(
              %{
                entity_uuid: ctx.entity.uuid,
                title: "BulkDel #{n}",
                slug: "bulkdel-#{n}",
                created_by_uuid: ctx.actor_uuid
              },
              actor_uuid: ctx.actor_uuid
            )

          r.uuid
        end

      {2, _} = EntityData.bulk_delete(uuids, actor_uuid: ctx.other_actor)

      assert_activity_logged("entity_data.bulk_deleted",
        actor_uuid: ctx.other_actor,
        metadata_has: %{"count" => 2, "uuid_count" => 2}
      )
    end
  end

  describe "module toggle" do
    test "enable_system logs module.entities.enabled with actor", ctx do
      {:ok, _} = Entities.enable_system(actor_uuid: ctx.actor_uuid)

      assert_activity_logged("module.entities.enabled",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"setting" => "entities_enabled"}
      )
    end

    test "disable_system logs module.entities.disabled with actor", ctx do
      {:ok, _} = Entities.disable_system(actor_uuid: ctx.actor_uuid)

      assert_activity_logged("module.entities.disabled",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"setting" => "entities_enabled"}
      )
    end
  end
end
