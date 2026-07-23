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

    test "unchecking the only field on the form (checkbox-only entity) still clears it" do
      # When EVERY input on the form is a checkbox group (no text/other
      # field to anchor a "phoenix_kit_entity_data" key), unticking the
      # last box makes phx-change submit params with no
      # "phoenix_kit_entity_data" key at all — just LiveView's internal
      # "_target". The fallback `handle_event("autosave", _params, socket)`
      # clause must still run the merge/persist path (with an empty map)
      # rather than no-op'ing, or this case would silently never clear.
      fields = [
        %{
          "type" => "checkbox",
          "key" => "tools",
          "label" => "Tools",
          "options" => ["Hammer", "Drill"]
        }
      ]

      entity = create_entity!(fields)
      record = create_record!(entity, %{"tools" => ["Hammer"]})
      socket = socket(record, entity)

      {:noreply, socket} =
        LiveDataForm.handle_event("autosave", %{"_target" => ["nonexistent"]}, socket)

      assert socket.assigns.record.data["tools"] == []
      assert_received {:live_data_form, :saved, updated_record}
      assert updated_record.data["tools"] == []

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["tools"] == []
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

    test "an EntityData.changeset failure logs and keeps the previous record" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"})
      # entity_uuid pointing at a deleted/unknown entity trips
      # `validate_entity_reference`/`validate_data_against_entity` inside
      # `EntityData.changeset/2`, forcing the `{:error, changeset}` branch —
      # this is the FINAL, hard-blocking validator (unlike
      # `FormBuilder.validate_data/2` below, which never blocks a save).
      broken_record = %{record | entity_uuid: Ecto.UUID.generate()}
      socket = socket(broken_record, entity)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:noreply, updated_socket} =
            LiveDataForm.handle_event(
              "autosave",
              %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "New"}}},
              socket
            )

          send(self(), {:updated_socket, updated_socket})
        end)

      assert log =~ "LiveDataForm autosave failed"
      assert_received {:updated_socket, socket}
      assert socket.assigns.record == broken_record
      refute_received {:live_data_form, :saved, _}

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["name"] == "Old"
    end

    test "a number field's string value is coerced to a float on persist" do
      fields = [%{"type" => "number", "key" => "qty", "label" => "Quantity"}]
      entity = create_entity!(fields)
      record = create_record!(entity, %{})
      socket = socket(record, entity)

      {:noreply, socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{"phoenix_kit_entity_data" => %{"data" => %{"qty" => "5"}}},
          socket
        )

      assert socket.assigns.record.data["qty"] == 5.0

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["qty"] == 5.0
    end

    test "data that fails FormBuilder.validate_data/2 is persisted as-is and logs a warning" do
      # `radio` fields are validated strictly by `FormBuilder.validate_type/2`
      # (value must be one of `options`, absent `allow_other`) but have NO
      # type-specific branch in `EntityData.changeset/2`'s own
      # `validate_field_type/2` — so an out-of-options value fails the
      # FormBuilder pass while still sailing through `EntityData.update/3`,
      # exercising the "log and persist raw" branch specifically (as
      # opposed to the hard-blocking changeset failure above).
      fields = [
        %{
          "type" => "radio",
          "key" => "priority",
          "label" => "Priority",
          "options" => ["Low", "High"]
        }
      ]

      entity = create_entity!(fields)
      record = create_record!(entity, %{})
      socket = socket(record, entity)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          {:noreply, updated_socket} =
            LiveDataForm.handle_event(
              "autosave",
              %{"phoenix_kit_entity_data" => %{"data" => %{"priority" => "Medium"}}},
              socket
            )

          send(self(), {:updated_socket, updated_socket})
        end)

      assert log =~ "failed FormBuilder validation"
      assert_received {:updated_socket, updated_socket}
      assert updated_socket.assigns.record.data["priority"] == "Medium"

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["priority"] == "Medium"
    end
  end

  describe "submit" do
    # Contract (revised): submit persists the params `phx-submit` just
    # sent — same merge-over-`record.data` path as autosave — so the
    # last edit is never lost to the 500ms debounce window, then sends
    # `:submitted` with the freshly-updated record. It never touches
    # `status`.
    test "persists the submitted params and sends :submitted with the updated record" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"})
      socket = socket(record, entity, submit_label: "Kinnitan")

      {:noreply, socket} =
        LiveDataForm.handle_event(
          "submit",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "Final"}}},
          socket
        )

      assert_received {:live_data_form, :submitted, submitted_record}
      assert submitted_record.uuid == record.uuid
      assert submitted_record.data["name"] == "Final"
      refute_received {:live_data_form, :saved, _}

      assert socket.assigns.record.data["name"] == "Final"

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["name"] == "Final"
    end

    test "submitting a published record persists data without changing its status" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"}, "published")
      socket = socket(record, entity, submit_label: "Kinnitan")

      {:noreply, _socket} =
        LiveDataForm.handle_event(
          "submit",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "Final"}}},
          socket
        )

      assert_received {:live_data_form, :submitted, submitted_record}
      assert submitted_record.status == "published"
      assert submitted_record.data["name"] == "Final"

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.status == "published"
      assert reloaded.data["name"] == "Final"
    end

    test "a failed save logs, keeps the previous record, and never sends :submitted" do
      entity = create_entity!()
      record = create_record!(entity, %{"name" => "Old"})
      # Same broken-reference trick as the autosave failure test — trips
      # `EntityData.changeset/2`'s entity validation so `update/3` returns
      # `{:error, changeset}`.
      broken_record = %{record | entity_uuid: Ecto.UUID.generate()}
      socket = socket(broken_record, entity, submit_label: "Kinnitan")

      {:noreply, socket} =
        LiveDataForm.handle_event(
          "submit",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "Final"}}},
          socket
        )

      refute_received {:live_data_form, :submitted, _}
      refute_received {:live_data_form, :saved, _}
      assert socket.assigns.record == broken_record

      reloaded = EntityData.get!(record.uuid)
      assert reloaded.data["name"] == "Old"
    end
  end
end
