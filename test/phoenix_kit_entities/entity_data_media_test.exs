defmodule PhoenixKitEntities.EntityDataMediaTest do
  @moduledoc """
  The changeset-side media gate (`validate_media_field/3`): image/video
  fields store a storage-file uuid reference, and the FINAL write gate
  is the EntityData changeset — junk must refuse here even when a
  caller bypassed `FormBuilder.cast_field/2` (C11 pin, 2026-08-19).
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "ed_media",
          display_name: "ED Media",
          display_name_plural: "ED Media",
          fields_definition: [
            %{"type" => "image", "key" => "swatch", "label" => "Swatch"},
            %{"type" => "video", "key" => "clip", "label" => "Clip"}
          ],
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    %{entity: entity, actor: actor_uuid}
  end

  defp create(entity, actor, data) do
    EntityData.create(
      %{
        entity_uuid: entity.uuid,
        title: "Rec",
        slug: "rec-#{System.unique_integer([:positive])}",
        status: "published",
        data: data,
        created_by_uuid: actor
      },
      actor_uuid: actor
    )
  end

  test "uuid references pass, junk refuses, absent/nil pass", %{entity: entity, actor: actor} do
    uuid = Ecto.UUID.generate()

    assert {:ok, rec} = create(entity, actor, %{"swatch" => uuid, "clip" => nil})
    assert rec.data["swatch"] == uuid

    assert {:error, changeset} = create(entity, actor, %{"swatch" => "not-a-uuid"})
    assert %{data: [message]} = errors_on(changeset)
    assert message =~ "media file reference"

    assert {:error, _} = create(entity, actor, %{"clip" => 42})
    assert {:ok, _} = create(entity, actor, %{})
  end
end
