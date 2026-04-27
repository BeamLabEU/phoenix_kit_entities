defmodule PhoenixKitEntities.Web.DataFormLiveTest do
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    actor_uuid = Ecto.UUID.generate()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "df_test",
          display_name: "DF Test",
          display_name_plural: "DF Tests",
          fields_definition: [
            %{"type" => "text", "key" => "name", "label" => "Name"},
            %{"type" => "boolean", "key" => "active", "label" => "Active"}
          ],
          status: "published",
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, record} =
      EntityData.create(
        %{
          entity_uuid: entity.uuid,
          title: "Hello",
          slug: "hello",
          status: "published",
          data: %{
            "_primary_language" => "en-US",
            "en-US" => %{
              "_title" => "Hello",
              "_slug" => "hello",
              "name" => "Acme",
              "active" => true
            },
            "es-ES" => %{"_title" => "Hola"}
          },
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    {:ok, entity: entity, record: record, actor_uuid: actor_uuid}
  end

  describe "mount edit form" do
    test "renders title + page heading", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, edit_url(ctx.entity, ctx.record))

      assert html =~ "Edit DF Test"
      assert html =~ ~s|value="Hello"|
    end

    test "form has phx-disable-with on submit (delta-pin C5)", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, _view, html} = live(conn, edit_url(ctx.entity, ctx.record))

      assert html =~ ~r|type="submit"[^>]*phx-disable-with=|
    end
  end

  describe "switch_language event" do
    test "ignores unknown language without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      render_hook(view, "switch_language", %{"lang" => "totally-fake"})
      assert render(view) =~ "Edit DF Test"
    end

    test "accepts a known language and remains on the form", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      # Without multilang enabled the LV no-ops; the assertion is "no crash".
      render_hook(view, "switch_language", %{"lang" => "en-US"})
      assert render(view) =~ "Edit DF Test"
    end
  end

  describe ":data_form_change broadcast (collab editing)" do
    # This test would have caught the `:created_by` cast crash. The
    # handler runs `Ecto.Changeset.cast(params, [..., :created_by_uuid])`;
    # if any atom in that list isn't a schema field, Ecto raises
    # ArgumentError and the LV crashes the moment another tab broadcasts.
    test "applies remote params without crashing the LV", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      payload = %{
        params: %{
          "entity_uuid" => ctx.entity.uuid,
          "title" => "Hello (remote edit)",
          "slug" => "hello",
          "status" => "published",
          "data" => %{
            "_primary_language" => "en-US",
            "en-US" => %{"_title" => "Hello (remote edit)", "name" => "Acme remote"}
          }
        }
      }

      # Source string differs from this LV's `live_source` so the handler
      # treats it as an external broadcast and applies the params.
      send(view.pid, {:data_form_change, ctx.entity.uuid, ctx.record.uuid, payload, "phx-other"})

      # If the cast crashed, render/1 would raise. Title (top-level DB
      # column) is rendered in the basic-info section regardless of
      # multilang state, so we use it as the proof-of-life assertion.
      html = render(view)
      assert html =~ "Hello (remote edit)"
    end

    test "ignores broadcasts for a different record", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      other_uuid = Ecto.UUID.generate()

      send(
        view.pid,
        {:data_form_change, ctx.entity.uuid, other_uuid, %{params: %{"title" => "Other"}},
         "phx-other"}
      )

      # Original title still rendered.
      html = render(view)
      assert html =~ "Hello"
      refute html =~ "Other"
    end

    test "ignores broadcasts for a different entity", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      send(
        view.pid,
        {:data_form_change, Ecto.UUID.generate(), ctx.record.uuid,
         %{params: %{"title" => "Wrong entity"}}, "phx-other"}
      )

      refute render(view) =~ "Wrong entity"
    end

    test "ignores broadcasts from this LV's own source (echo prevention)",
         %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      # Read the live_source assign by inspecting the running socket via
      # Phoenix.LiveViewTest.run/3 — we need the actual value to forge an
      # echo. Use it as the broadcast source.
      live_source = :sys.get_state(view.pid).socket.assigns.live_source

      send(
        view.pid,
        {:data_form_change, ctx.entity.uuid, ctx.record.uuid,
         %{params: %{"title" => "Echo from self"}}, live_source}
      )

      refute render(view) =~ "Echo from self"
    end
  end

  describe ":data_updated / :data_deleted broadcasts" do
    test "data_updated for a different record is ignored", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      send(view.pid, {:data_updated, ctx.entity.uuid, Ecto.UUID.generate()})
      assert render(view) =~ "Hello"
    end

    test "data_deleted for this record redirects to the data list", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      send(view.pid, {:data_deleted, ctx.entity.uuid, ctx.record.uuid})

      # The handler issues a live_redirect with a flash; the redirect
      # surfaces as a {:live_redirect, _} exit signal when render/1 runs.
      {path, _flash} = assert_redirect(view)
      assert path =~ "/admin/entities/#{ctx.entity.name}/data"
    end
  end

  describe "handle_info catch-all" do
    test "ignores unrelated messages without crashing", %{conn: conn} = ctx do
      conn = put_test_scope(conn, fake_scope(user_uuid: ctx.actor_uuid))
      {:ok, view, _html} = live(conn, edit_url(ctx.entity, ctx.record))

      send(view.pid, {:totally_unrelated, "junk", :payload})
      assert render(view) =~ "Edit DF Test"
    end
  end

  # ── helpers ──────────────────────────────────────────────────

  defp edit_url(entity, record),
    do: "/en/admin/entities/#{entity.name}/data/#{record.uuid}/edit"
end
