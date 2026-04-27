defmodule PhoenixKitEntities.Web.EntityFormLiveTest do
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKitEntities, as: Entities

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "ef_test",
          display_name: "EF Test",
          display_name_plural: "EF Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"}
          ],
          status: "published",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, actor_uuid: actor_uuid}
  end

  describe "mount new" do
    test "renders the new-entity page", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/entities/new")

      assert html =~ "Create New Entity"
    end

    test "submit button has phx-disable-with (delta-pin C5)", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/entities/new")

      assert html =~ ~r|type="submit"[^>]*phx-disable-with=|
    end
  end

  describe "mount edit" do
    test "renders existing entity values pre-filled", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, "/en/admin/entities/#{ctx.entity.uuid}/edit")

      assert html =~ "Edit Entity"
      assert html =~ ~s|value="EF Test"|
      assert html =~ ~s|value="ef_test"|
    end
  end

  describe "validate event" do
    test "validate sets :action so inline errors render (delta-pin C5)",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/entities/#{ctx.entity.uuid}/edit")

      # Submit a name that violates `validate_format` (uppercase letters
      # forbidden). Without `:action = :validate` on the changeset, the
      # `<.input>` core component swallows the error silently.
      view
      |> form("form[phx-change='validate']", %{"entities" => %{"name" => "INVALID-name"}})
      |> render_change()

      html = render(view)
      # Either the inline error renders with the format message, or at
      # minimum the changeset has its action set (we can't read socket
      # state, so check the rendered DOM for an error class).
      assert html =~ "input-error" or html =~ "must contain only lowercase"
    end
  end

  describe "switch_language event" do
    test "ignores unknown language and stays on the form", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/entities/#{ctx.entity.uuid}/edit")

      render_hook(view, "switch_language", %{"lang" => "totally-fake"})
      assert render(view) =~ "Edit Entity"
    end
  end

  describe "handle_info catch-all" do
    test "ignores unrelated PubSub messages without crashing",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, "/en/admin/entities/#{ctx.entity.uuid}/edit")

      send(view.pid, {:unrelated_message, :payload})
      assert render(view) =~ "Edit Entity"
    end
  end
end
