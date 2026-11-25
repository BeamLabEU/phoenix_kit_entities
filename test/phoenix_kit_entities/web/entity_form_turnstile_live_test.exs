defmodule PhoenixKitEntities.Web.EntityFormTurnstileLiveTest do
  @moduledoc """
  The builder's Cloudflare Turnstile controls (`Web.EntityForm`): the option
  sits with the other security options, saves with the entity, and warns while
  it is on but there is nothing to verify with.
  """
  use PhoenixKitEntities.LiveCase, async: false

  alias PhoenixKit.Integrations
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.Test.TurnstileStub

  setup do
    TurnstileStub.install()
    actor_uuid = Ecto.UUID.generate()
    connection = TurnstileStub.verified_connection!("Contact forms", "0x4AAAA-site-key")

    {:ok, actor_uuid: actor_uuid, connection: connection}
  end

  defp create_entity(actor_uuid, settings) do
    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "ts_builder",
          display_name: "TS Builder",
          display_name_plural: "TS Builders",
          status: "published",
          fields_definition: [%{"type" => "text", "key" => "name", "label" => "Name"}],
          settings:
            Map.merge(
              %{"public_form_enabled" => true, "public_form_fields" => ["name"]},
              settings
            ),
          created_by_uuid: actor_uuid
        },
        actor_uuid: actor_uuid
      )

    entity
  end

  defp edit(conn, entity, actor_uuid) do
    conn = put_test_scope(conn, fake_scope(user_uuid: actor_uuid))
    {:ok, view, html} = live(conn, "/en/admin/entities/#{entity.uuid}/edit")
    {view, html}
  end

  defp pick_connection(view, uuid) do
    render_hook(view, "update_security_action", %{
      "setting" => "public_form_turnstile_connection",
      "public_form_turnstile_connection" => uuid
    })
  end

  test "the option is offered next to the other security options, off by default",
       %{conn: conn, actor_uuid: actor_uuid} do
    entity = create_entity(actor_uuid, %{})
    {view, _html} = edit(conn, entity, actor_uuid)

    assert has_element?(view, "#public-form-turnstile input[name=public_form_turnstile]")

    refute has_element?(
             view,
             "#public-form-turnstile input[name=public_form_turnstile][checked]"
           )

    refute has_element?(view, "#public-form-turnstile select")
  end

  test "the switch, the connection and the action save with the entity",
       %{conn: conn, actor_uuid: actor_uuid, connection: connection} do
    entity = create_entity(actor_uuid, %{})
    {view, _html} = edit(conn, entity, actor_uuid)

    render_hook(view, "toggle_security_setting", %{"setting" => "public_form_turnstile"})

    assert has_element?(
             view,
             "#public-form-turnstile select[name=public_form_turnstile_connection] option",
             "Contact forms"
           )

    pick_connection(view, connection)

    render_hook(view, "update_security_action", %{
      "setting" => "public_form_turnstile_action",
      "public_form_turnstile_action" => "save_log"
    })

    view
    |> form("form[phx-change='validate']", %{"entities" => %{"display_name" => "Saved"}})
    |> render_submit()

    assert %{
             "public_form_turnstile" => true,
             "public_form_turnstile_connection" => ^connection,
             "public_form_turnstile_action" => "save_log"
           } = Entities.get_entity!(entity.uuid).settings
  end

  test "warns while the option is on and no connection is selected",
       %{conn: conn, actor_uuid: actor_uuid, connection: connection} do
    entity = create_entity(actor_uuid, %{"public_form_turnstile" => true})
    {view, _html} = edit(conn, entity, actor_uuid)

    assert has_element?(view, "#turnstile-not-ready", "Select a Turnstile connection")

    pick_connection(view, connection)

    refute has_element?(view, "#turnstile-not-ready")
  end

  test "warns when no verified connection exists at all",
       %{conn: conn, actor_uuid: actor_uuid, connection: connection} do
    :ok = Integrations.remove_connection(connection)
    entity = create_entity(actor_uuid, %{"public_form_turnstile" => true})
    {view, _html} = edit(conn, entity, actor_uuid)

    assert has_element?(view, "#turnstile-not-ready", "No verified Cloudflare Turnstile")
  end

  test "warns about a selected connection that is gone",
       %{conn: conn, actor_uuid: actor_uuid, connection: connection} do
    entity =
      create_entity(actor_uuid, %{
        "public_form_turnstile" => true,
        "public_form_turnstile_connection" => connection
      })

    # Another verified connection remains, so the form can be fixed by picking it.
    TurnstileStub.verified_connection!("Other site", "0x4AAAA-other-key")
    :ok = Integrations.remove_connection(connection)
    {view, _html} = edit(conn, entity, actor_uuid)

    assert has_element?(view, "#turnstile-not-ready", "gone or no longer verified")
  end

  test "no warning while the option is off", %{conn: conn, actor_uuid: actor_uuid} do
    entity = create_entity(actor_uuid, %{})
    {view, _html} = edit(conn, entity, actor_uuid)

    refute has_element?(view, "#turnstile-not-ready")
  end

  test "the trigger counters show", %{conn: conn, actor_uuid: actor_uuid} do
    entity = create_entity(actor_uuid, %{})

    Entities.bump_public_form_stats(entity.uuid, [
      "turnstile_triggers",
      "turnstile_unavailable_triggers"
    ])

    {_view, html} = edit(conn, entity, actor_uuid)

    assert html =~ "Turnstile: 1"
    assert html =~ "Turnstile unavailable: 1"
  end
end
