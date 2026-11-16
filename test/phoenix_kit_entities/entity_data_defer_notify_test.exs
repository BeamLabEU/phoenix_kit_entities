defmodule PhoenixKitEntities.EntityDataDeferNotifyTest do
  @moduledoc """
  `defer_notify: true` on `EntityData.create/2` and `update/3`, and
  `EntityData.notify_committed/2`: a caller writing inside a transaction of
  its own announces the record only after that transaction commits.
  """

  use PhoenixKitEntities.DataCase, async: false

  alias Ecto.UUID
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.Events

  setup do
    actor_uuid = UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "defer_notify_test",
          display_name: "Defer Notify Test",
          display_name_plural: "Defer Notify Tests",
          fields_definition: [%{"type" => "text", "key" => "name", "label" => "Name"}],
          status: "published",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    :ok = Events.subscribe_to_entity_data(entity.uuid)

    {:ok, entity: entity, actor_uuid: actor_uuid}
  end

  defp attrs(ctx, n) do
    %{
      entity_uuid: ctx.entity.uuid,
      title: "Record #{n}",
      slug: "record-#{n}",
      status: "published",
      data: %{"name" => "Item #{n}"},
      created_by_uuid: ctx.actor_uuid
    }
  end

  test "a plain create announces the record at once", ctx do
    {:ok, record} = EntityData.create(attrs(ctx, 1), actor_uuid: ctx.actor_uuid)

    assert_receive {:data_created, entity_uuid, data_uuid}, 500
    assert {entity_uuid, data_uuid} == {ctx.entity.uuid, record.uuid}
  end

  test "a deferred create announces nothing until notify_committed/2", ctx do
    {:ok, record} =
      EntityData.create(attrs(ctx, 1), actor_uuid: ctx.actor_uuid, defer_notify: true)

    refute_receive {:data_created, _, _}, 100

    assert :ok = EntityData.notify_committed(record, :created)
    assert_receive {:data_created, entity_uuid, data_uuid}, 500
    assert {entity_uuid, data_uuid} == {ctx.entity.uuid, record.uuid}
  end

  test "a deferred update announces nothing until notify_committed/2", ctx do
    {:ok, record} = EntityData.create(attrs(ctx, 1), actor_uuid: ctx.actor_uuid)
    assert_receive {:data_created, _, _}, 500

    {:ok, updated} =
      EntityData.update(record, %{title: "Renamed"},
        actor_uuid: ctx.actor_uuid,
        defer_notify: true
      )

    refute_receive {:data_updated, _, _}, 100

    assert :ok = EntityData.notify_committed(updated, :updated)
    assert_receive {:data_updated, entity_uuid, data_uuid}, 500
    assert {entity_uuid, data_uuid} == {ctx.entity.uuid, record.uuid}
  end

  test "inside the caller's transaction: announced after the commit, never for a rollback",
       ctx do
    {:ok, record} =
      Repo.transaction(fn ->
        {:ok, record} = EntityData.create(attrs(ctx, 1), defer_notify: true)
        record
      end)

    refute_receive {:data_created, _, _}, 100
    EntityData.notify_committed(record, :created)
    assert_receive {:data_created, _, _}, 500

    assert {:error, :rolled_back} =
             Repo.transaction(fn ->
               {:ok, _record} = EntityData.create(attrs(ctx, 2), defer_notify: true)
               Repo.rollback(:rolled_back)
             end)

    refute_receive {:data_created, _, _}, 100
    assert EntityData.get_by_slug(ctx.entity.uuid, "record-2") == nil
  end

  test "nil is accepted and does nothing" do
    assert :ok = EntityData.notify_committed(nil, :created)
    refute_receive {:data_created, _, _}, 50
  end
end
