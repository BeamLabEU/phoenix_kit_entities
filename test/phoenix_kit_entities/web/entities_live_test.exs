defmodule PhoenixKitEntities.Web.EntitiesLiveTest do
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKitEntities, as: Entities

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, published} =
      Entities.create_entity(
        %{
          name: "live_pub",
          display_name: "Live Pub",
          display_name_plural: "Live Pubs",
          fields_definition: [%{"type" => "text", "key" => "name", "label" => "Name"}],
          status: "published",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, archived} =
      Entities.create_entity(
        %{
          name: "live_arch",
          display_name: "Live Arch",
          display_name_plural: "Live Archs",
          fields_definition: [%{"type" => "text", "key" => "name", "label" => "Name"}],
          status: "archived",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, published: published, archived: archived, actor_uuid: actor_uuid}
  end

  describe "mount" do
    test "renders entity manager with both entities", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/entities")

      assert html =~ "Entity Manager"
      assert html =~ "Live Pub"
      assert html =~ "Live Arch"
    end
  end

  describe "archive_entity" do
    test "flips status, fires entity.updated activity, and shows flash",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/entities")

      # Two buttons match (table view + card view); target the table-view
      # one via the `data-tip` attribute.
      view
      |> element(
        "button[phx-click='archive_entity'][phx-value-uuid='#{ctx.published.uuid}'][data-tip='Archive']"
      )
      |> render_click()

      # Activity row reflects the threaded actor (delta-pin: actor_opts/1).
      assert_activity_logged("entity.updated",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: ctx.published.uuid,
        metadata_has: %{"status" => "archived"}
      )

      assert render(view) =~ "archived successfully"
      assert Entities.get_entity!(ctx.published.uuid).status == "archived"
    end

    test "archive button has phx-disable-with set", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/entities")

      # delta-pin: phx-disable-with attr present on every async/destructive
      # phx-click button (C5). Regex-match because the attr is one of many.
      assert html =~
               ~r/phx-click="archive_entity"[^>]*phx-value-uuid="#{ctx.published.uuid}"[^>]*phx-disable-with=/
    end
  end

  describe "restore_entity" do
    test "flips status from archived → published with the threaded actor",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/entities")

      view
      |> element(
        "button[phx-click='restore_entity'][phx-value-uuid='#{ctx.archived.uuid}'][data-tip='Restore']"
      )
      |> render_click()

      assert_activity_logged("entity.updated",
        actor_uuid: ctx.actor_uuid,
        resource_uuid: ctx.archived.uuid,
        metadata_has: %{"status" => "published"}
      )

      assert render(view) =~ "restored successfully"
    end
  end
end
