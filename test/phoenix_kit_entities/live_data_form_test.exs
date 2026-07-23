defmodule PhoenixKitEntities.LiveDataFormTest do
  @moduledoc """
  `PhoenixKitEntities.Components.LiveDataForm` is a stateful `LiveComponent`,
  so exercising it needs `Phoenix.LiveViewTest.render_component/2` (which
  runs `update/2` + `render/1` through `Phoenix.LiveView.Diff`) rather than
  the plain-function-component pattern used by `FormBuilder.build_field/3`
  in the other `form_builder_*_test.exs` files.

  `render_component/2` only needs an `@endpoint` module attribute at
  compile time — it never dereferences the endpoint as a running process
  unless the component itself calls something endpoint-dependent (routing
  helpers, etc.), which this component doesn't. So these tests stay in the
  DB-free unit bucket as long as `record.entity` is preloaded (avoiding the
  `Entities.get_entity!/2` DB fallback in `resolve_entity/3`) — exactly the
  case a real caller hits when it preloads `:entity` before rendering.

  Autosave persistence, the `:submitted` message, and status-preservation
  are `:integration` tests in `live_data_form_integration_test.exs` (they
  need a live process + the database for `EntityData.update/3`).
  """
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias PhoenixKitEntities.Components.LiveDataForm
  alias PhoenixKitEntities.EntityData

  @endpoint PhoenixKitEntities.Test.Endpoint

  defp entity(fields) do
    %PhoenixKitEntities{uuid: Ecto.UUID.generate(), fields_definition: fields}
  end

  defp record(entity, data \\ %{}) do
    %EntityData{
      uuid: Ecto.UUID.generate(),
      entity_uuid: entity.uuid,
      entity: entity,
      title: "Survey",
      status: "published",
      data: data
    }
  end

  defp render_form(assigns) do
    render_component(
      LiveDataForm,
      Map.put(assigns, :id, "live-data-form-#{System.unique_integer([:positive])}")
    )
  end

  describe ":readonly mode" do
    test "renders a heading and no inputs" do
      fields = [%{"type" => "heading", "key" => "sec", "label" => "Section One"}]
      e = entity(fields)
      r = record(e)

      html =
        render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "<h3"
      assert html =~ "Section One"
      refute html =~ "<input"
      refute html =~ "<textarea"
      refute html =~ "<select"
    end

    test "shows a field's stored value as label: value" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e, %{"name" => "Jaan"})

      html =
        render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "Name"
      assert html =~ "Jaan"
      refute html =~ "<input"
    end

    test "an empty field renders the em dash placeholder" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e, %{})

      html =
        render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "—"
    end

    test "a checkbox list is joined with commas" do
      fields = [
        %{
          "type" => "checkbox",
          "key" => "tools",
          "label" => "Tools",
          "options" => ["Hammer", "Drill", "Saw"]
        }
      ]

      e = entity(fields)
      r = record(e, %{"tools" => ["Hammer", "Saw"]})

      html =
        render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "Hammer, Saw"
      refute html =~ "<input"
    end

    test "a textarea value keeps its line breaks and is not comma-joined" do
      fields = [%{"type" => "textarea", "key" => "notes", "label" => "Notes"}]
      e = entity(fields)
      r = record(e, %{"notes" => "line one\nline two"})

      html =
        render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "line one\nline two"
      refute html =~ "<textarea"
    end

    test "a value outside the fixed options (allow_other free text) is shown as-is" do
      fields = [
        %{
          "type" => "radio",
          "key" => "color",
          "label" => "Color",
          "options" => ["Red", "Blue"],
          "allow_other" => true
        }
      ]

      e = entity(fields)
      r = record(e, %{"color" => "Crimson"})

      html =
        render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "Crimson"
    end
  end

  describe ":edit mode" do
    # `lang: nil` throughout this block (rather than a real locale like
    # "et") is deliberate: `FormBuilder.build_fields/3` only touches
    # `Multilang`/the database when `lang_code` is non-nil (it short-circuits
    # on `nil` in both `maybe_add_primary_placeholders/4` and
    # `maybe_apply_language_view/3`). None of these assertions are about
    # language-specific behavior, so `nil` keeps them fast and DB-free. The
    # "lang pass-through" test below covers the non-nil path once.

    test "renders an autosaving, debounced form targeting the component" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e)

      html = render_form(%{record: r, mode: :edit, lang: nil, actor: nil, submit_label: nil})

      assert html =~ ~s(phx-change="autosave")
      assert html =~ ~s(phx-submit="submit")
      assert html =~ ~s(phx-debounce="500")
      assert html =~ ~s(name="phoenix_kit_entity_data[data][name]")
    end

    test "hides the submit button when submit_label is nil" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e)

      html = render_form(%{record: r, mode: :edit, lang: nil, actor: nil, submit_label: nil})

      refute html =~ ~s(type="submit")
    end

    test "shows the submit button with the given label when submit_label is set" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e)

      html =
        render_form(%{record: r, mode: :edit, lang: nil, actor: nil, submit_label: "Kinnitan"})

      assert html =~ ~s(type="submit")
      assert html =~ "Kinnitan"
    end

    test "renders a heading field with no input, same as readonly mode" do
      fields = [
        %{"type" => "heading", "key" => "sec", "label" => "Section One"},
        %{"type" => "text", "key" => "name", "label" => "Name"}
      ]

      e = entity(fields)
      r = record(e)

      html = render_form(%{record: r, mode: :edit, lang: nil, actor: nil, submit_label: nil})

      assert html =~ "<h3"
      assert html =~ "Section One"
    end
  end

  describe "lang pass-through" do
    # Exercises the one path where `lang` reaching `FormBuilder.build_fields/3`
    # as a real locale actually does something observable pre-render: it
    # probes `Multilang`/`Languages`, which — with no test DB in this
    # sandbox — blocks on a connection-pool queue timeout before falling
    # back safely. That's a pre-existing characteristic of
    # `FormBuilder.build_fields/3` (see `form_builder_multilang_test.exs`
    # for the DB-backed multilang suite), not something this component
    # introduces; kept to a single test so it doesn't slow down the rest
    # of this file.
    test "a non-nil lang still renders the form correctly" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e, %{"name" => "Jaan"})

      html = render_form(%{record: r, mode: :edit, lang: "et", actor: nil, submit_label: nil})

      assert html =~ ~s(phx-change="autosave")
      assert html =~ "Jaan"
    end
  end

  describe "entity resolution" do
    test "reuses the preloaded :entity association without hitting the database" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      # entity_uuid points nowhere in the DB — if resolve_entity fell back
      # to a query, this would raise Ecto.NoResultsError (no DB is even
      # configured to connect to in this async unit test).
      r = record(e)

      html = render_form(%{record: r, mode: :readonly, lang: "et", actor: nil, submit_label: nil})

      assert html =~ "Name"
    end
  end

  describe "mode guard (security)" do
    # `handle_event/3` is reachable for any event this component defines
    # regardless of what the rendered template wires up — LiveView
    # dispatches a component event by `cid` alone. A `:readonly` instance
    # never renders a `<form phx-change="autosave" ...>`, but that alone
    # doesn't stop a crafted client-side push from reaching this
    # `handle_event/3` clause. These are handle_event/3 called directly
    # (no live process needed — mirrors the DB-backed tests in
    # `live_data_form_integration_test.exs`), and specifically DON'T need
    # the database: the mode guard must reject the event before
    # `persist_data/3` (and therefore `EntityData.update/3`) ever runs.
    defp readonly_socket(record, entity) do
      %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          record: record,
          entity: entity,
          mode: :readonly,
          lang: nil,
          actor: nil,
          submit_label: nil
        }
      }
    end

    test "autosave is a no-op in :readonly mode" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e, %{"name" => "Old"})
      socket = readonly_socket(r, e)

      {:noreply, updated_socket} =
        LiveDataForm.handle_event(
          "autosave",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "Hacked"}}},
          socket
        )

      assert updated_socket.assigns.record.data == %{"name" => "Old"}
      refute_received {:live_data_form, :saved, _}
    end

    test "submit is a no-op in :readonly mode" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e, %{"name" => "Old"})
      socket = readonly_socket(r, e)

      {:noreply, updated_socket} =
        LiveDataForm.handle_event(
          "submit",
          %{"phoenix_kit_entity_data" => %{"data" => %{"name" => "Hacked"}}},
          socket
        )

      assert updated_socket.assigns.record.data == %{"name" => "Old"}
      refute_received {:live_data_form, :submitted, _}
    end

    test "the fallback autosave clause (no phoenix_kit_entity_data key) is also a no-op in :readonly mode" do
      fields = [
        %{"type" => "checkbox", "key" => "tools", "label" => "Tools", "options" => ["Hammer"]}
      ]

      e = entity(fields)
      r = record(e, %{"tools" => ["Hammer"]})
      socket = readonly_socket(r, e)

      {:noreply, updated_socket} =
        LiveDataForm.handle_event("autosave", %{"_target" => ["nonexistent"]}, socket)

      assert updated_socket.assigns.record.data == %{"tools" => ["Hammer"]}
      refute_received {:live_data_form, :saved, _}
    end
  end

  describe "optional attrs (lang, actor, submit_label) can be omitted entirely" do
    # `update/2` only sets a key on `socket.assigns` for what the caller
    # actually passes in — a caller that omits `:lang`/`:actor`/
    # `:submit_label` (not even `nil`) used to leave `render/1`'s
    # `@lang`/`@submit_label` raising `KeyError`, since these are
    # documented as optional. `assign_new/3` in `update/2` now backfills
    # `nil` for each. `record` and `mode` stay genuinely required — no
    # test for omitting those; a caller bug there should crash.
    test ":readonly renders fine with only record and mode given" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e, %{"name" => "Jaan"})

      html =
        render_component(LiveDataForm, %{id: "live-data-form-omit-1", record: r, mode: :readonly})

      assert html =~ "Jaan"
    end

    test ":edit renders fine with only record and mode given — no submit button" do
      fields = [%{"type" => "text", "key" => "name", "label" => "Name"}]
      e = entity(fields)
      r = record(e)

      html =
        render_component(LiveDataForm, %{id: "live-data-form-omit-2", record: r, mode: :edit})

      assert html =~ ~s(phx-change="autosave")
      refute html =~ ~s(type="submit")
    end
  end
end
