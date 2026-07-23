defmodule PhoenixKitEntities.LiveDataFormIntegrationTest do
  @moduledoc """
  DB-backed behavior of `PhoenixKitEntities.Components.LiveDataForm`:
  autosave persistence, the `:submitted` message, and status preservation.

  `handle_event/3` is invoked directly against a hand-built
  `%Phoenix.LiveView.Socket{}` rather than through a mounted LiveView —
  `Phoenix.Component.assign/3` works on any `%Socket{}` regardless of
  whether it's attached to a live process, and the component neither
  subscribes to PubSub nor uses `@myself`/routing in a way that requires
  one. This mirrors calling a plain function with a hand-built first
  argument; it does not exercise the client-side `phx-change`/`phx-submit`
  wiring itself (covered structurally by the unit tests in
  `live_data_form_test.exs`), only the server-side effects once those
  events land.
  """
  use PhoenixKitEntities.DataCase, async: true

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.Components.LiveDataForm
  alias PhoenixKitEntities.EntityData

  @fields [
    %{"type" => "text", "key" => "name", "label" => "Name"},
    %{
      "type" => "checkbox",
      "key" => "tools",
      "label" => "Tools",
      "options" => ["Hammer", "Drill"]
    }
  ]

  defp create_entity!(fields \\ @fields) do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "live_data_form_test_#{System.unique_integer([:positive])}",
          display_name: "LiveDataForm Test",
          display_name_plural: "LiveDataForm Tests",
          fields_definition: fields,
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    entity
  end

  defp create_record!(entity, data, status \\ "published") do
    actor_uuid = Ecto.UUID.generate()

    {:ok, record} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "Survey response",
          status: status,
          data: data,
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    record
  end

  defp socket(record, entity, opts \\ []) do
    assigns =
      %{
        __changed__: %{},
        record: record,
        entity: entity,
        mode: :edit,
        lang: "et",
        actor: nil,
        submit_label: nil
      }
      |> Map.merge(Map.new(opts))

    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  describe "autosave" do
    test "persists the merged data and preserves status" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old", "tools" => ["Hammer"]}, "published")
      socket = socket(record, entity)

      {:noreply, socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "New", "tools" => ["Drill"]}}},
          socket
        )

      assert socket.assigns.record.data["name"] == "New"
      assert socket.assigns.record.data["tools"] == ["Drill"]
      assert socket.assigns.record.status == "published"
      assert_received {:live_data_form, :saved, updated_record}
      assert updated_record.uuid == record.uuid

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["name"] == "New"
      assert reloaded.status == "published"
    end

    test "does not reset status on a draft record" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"}, "draft")
      socket = socket(record, entity)

      {:noreply, _socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "New"}}},
          socket
        )

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["name"] == "New"
      assert reloaded.status == "draft"
    end

    test "unchecking every checkbox clears the stored list instead of leaving it untouched" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old", "tools" => ["Hammer", "Drill"]})
      socket = socket(record, entity)

      # Browsers omit the `tools` param entirely when every checkbox in the
      # group is unticked — no `data[tools][]` key at all.
      {:noreply, socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "Old"}}},
          socket
        )

      assert socket.assigns.record.data["tools"] == []
    end

    test "resolves an allow_other sentinel before persisting" do
      fields = [
        %{
          "type" => "radio",
          "key" => "color",
          "label" => "Color",
          "options" => ["Red", "Blue"],
          "allow_other" => true
        }
      ]

      entity = create_entity!(fields)
      record = create_record!(entity, %{})
      socket = socket(record, entity)

      {:noreply, socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{
            "phoenix_kit_entity_data" => %{
              "data" => %{"color" => "__other__", "color__other" => "Crimson"}
            }
          },
          socket
        )

      assert socket.assigns.record.data["color"] == "Crimson"
    end

    test "an update that fails validation logs and keeps the previous record" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"})
      # entity_uuid pointing at a deleted/unknown entity trips
      # `validate_entity_reference`/`validate_data_against_entity` inside
      # `EntityData.changeset/2`, forcing the `{:error, changeset}` branch.
      broken_record = %{record | entity_uuid: Ecto.UUID.generate()}
      socket = socket(broken_record, entity)

      {:noreply, socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "New"}}},
          socket
        )

      assert socket.assigns.record == broken_record
      refute_received {:live_data_form, :saved, _}

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["name"] == "Old"
    end
  end

  describe "submit" do
    # Per contract, `submit` only notifies the parent with the record
    # already on the socket — it does not itself persist anything (that's
    # autosave's job on every prior change). These tests fire "submit"
    # directly with no preceding "autosave" call, mirroring that division
    # of responsibility exactly.
    test "sends :submitted with the current record and does not write to the database" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"})
      socket = socket(record, entity, submit_label: "Kinnitan")

      {:noreply, socket} = LiveDataForm.handle_event("submit", %{}, socket)

      assert_received {:live_data_form, :submitted, submitted_record}
      assert submitted_record.uuid == record.uuid
      assert submitted_record.data == record.data
      assert socket.assigns.record == record
      refute_received {:live_data_form, :saved, _}

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data == record.data
    end

    test "submitting a published record does not change its status" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"}, "published")
      socket = socket(record, entity, submit_label: "Kinnitan")

      {:noreply, _socket} = LiveDataForm.handle_event("submit", %{}, socket)

      assert_received {:live_data_form, :submitted, submitted_record}
      assert submitted_record.status == "published"

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.status == "published"
    end
  end
end
