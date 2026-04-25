defmodule PhoenixKitEntities.Web.DataNavigatorLiveTest do
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "dn_test",
          display_name: "DN Test",
          display_name_plural: "DN Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"}
          ],
          status: "published",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    records =
      for n <- 1..3 do
        {:ok, r} =
          EntityData.create(
            %{
              entity_uuid: entity.uuid,
              title: "Record #{n}",
              slug: "record-#{n}",
              status: "published",
              data: %{"name" => "Item #{n}"},
              created_by_uuid: actor_uuid
            },
            actor_uuid: actor_uuid
          )

        r
      end

    {:ok, entity: entity, records: records, actor_uuid: actor_uuid}
  end

  describe "mount" do
    test "renders data navigator with entity title", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, navigator_url(ctx.entity))

      assert html =~ "DN Test"
      # All seeded records render in the table.
      assert html =~ "Record 1"
      assert html =~ "Record 2"
      assert html =~ "Record 3"
    end
  end

  describe "single-record archive_data / restore_data" do
    test "archive_data flips status, logs activity with actor_uuid + flash",
         %{conn: conn} = ctx do
      [record | _] = ctx.records
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      view
      |> element(
        "button[phx-click='archive_data'][phx-value-uuid='#{record.uuid}'][data-tip='Archive']"
      )
      |> render_click()

      assert_activity_logged("entity_data.updated",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: record.uuid,
        metadata_has: %{"status" => "archived"}
      )

      assert render(view) =~ "archived successfully"
      assert EntityData.get!(record.uuid).status == "archived"
    end

    test "restore_data flips back to published and logs", %{conn: conn} = ctx do
      [record | _] = ctx.records

      {:ok, _} =
        EntityData.update_data(record, %{status: "archived"}, actor_uuid: ctx.actor_uuid)

      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity, status: "archived"))

      view
      |> element(
        "button[phx-click='restore_data'][phx-value-uuid='#{record.uuid}'][data-tip='Restore']"
      )
      |> render_click()

      assert_activity_logged("entity_data.updated",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: record.uuid,
        metadata_has: %{"status" => "published"}
      )

      assert render(view) =~ "restored successfully"
    end

    test "single-record buttons carry phx-disable-with", %{conn: conn} = ctx do
      [record | _] = ctx.records
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, navigator_url(ctx.entity))

      # delta-pin C5: archive button has phx-disable-with attr.
      assert html =~
               ~r/phx-click="archive_data"[^>]*phx-value-uuid="#{record.uuid}"[^>]*phx-disable-with=/
    end
  end

  describe "bulk_action — actor_uuid threading + summary log" do
    test "bulk archive logs ONE bulk_status_changed row with actor + count",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      uuids = Enum.map(ctx.records, & &1.uuid)

      # Simulate selecting all 3 records, then bulk_action archive.
      for uuid <- uuids do
        render_hook(view, "toggle_select", %{"uuid" => uuid})
      end

      render_hook(view, "bulk_action", %{"action" => "archive"})

      assert_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"status" => "archived", "count" => 3, "uuid_count" => 3}
      )
    end

    test "bulk delete logs ONE bulk_deleted row", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      for r <- ctx.records do
        render_hook(view, "toggle_select", %{"uuid" => r.uuid})
      end

      render_hook(view, "bulk_action", %{"action" => "delete"})

      assert_activity_logged("entity_data.bulk_deleted",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"count" => 3, "uuid_count" => 3}
      )
    end

    test "bulk restore (change_status published) threads actor", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      [r | _] = ctx.records
      render_hook(view, "toggle_select", %{"uuid" => r.uuid})
      render_hook(view, "bulk_action", %{"action" => "restore"})

      assert_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.actor_uuid,
        metadata_has: %{"status" => "published", "count" => 1}
      )
    end

    test "bulk_action with no selection flashes error, no activity row",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      render_hook(view, "bulk_action", %{"action" => "archive"})

      assert render(view) =~ "No records selected"

      refute_activity_logged("entity_data.bulk_status_changed",
        actor_uuid: ctx.actor_uuid
      )
    end
  end

  describe "handle_info catch-all" do
    test "ignores unrelated PubSub messages without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, navigator_url(ctx.entity))

      send(view.pid, {:unknown_message, "noise"})
      assert render(view) =~ "DN Test"
    end
  end

  # ── helpers ──────────────────────────────────────────────────

  defp navigator_url(entity, opts \\ []) do
    base = "/en/admin/entities/#{entity.name}/data"

    case Keyword.get(opts, :status) do
      nil -> base
      status -> base <> "?status=#{status}"
    end
  end
end
