defmodule PhoenixKitEntities.Components.LiveDataForm do
  @moduledoc """
  Embeddable `LiveComponent` for viewing/editing a single `EntityData`
  record's custom fields — without the admin `DataForm` LiveView's parent
  picker, status control, presence/locking, or multilang tabs.

  The host LiveView owns everything outside the fields themselves:

  - Loading `record` (an `%EntityData{}`) — **expected to arrive with its
    `:entity` association preloaded**. When it is, this component reuses
    it and never touches the database — `:readonly` render is always
    DB-free, and so is the initial `:edit` render as long as `lang` is
    `nil` (a non-nil `lang` makes `FormBuilder.build_fields/3` do one
    cacheable `Multilang`/settings read; see the `lang` attribute below).
    When `:entity` isn't preloaded, it's instead loaded via
    `PhoenixKitEntities.get_entity!/2` (one query per `update/2`, unless
    the entity was already resolved for the same `entity_uuid` on a
    previous update) — a correctness fallback, not the intended calling
    convention.
  - PubSub — this component neither subscribes nor publishes.
    `PhoenixKitEntities.EntityData.update/3` already broadcasts changes.
  - `record.status` — autosave never changes it; a draft record stays a
    draft, a published one stays published.
  - Required-field completeness — **incremental autosave is guaranteed
    only for entities without required fields; entities with required
    fields save all-or-nothing per attempt, by design**. Every save runs
    the merged data through
    `PhoenixKitEntities.FormBuilder.validate_data/2` on a best-effort
    basis (for type coercion — number strings, URL normalization — never
    as a hard gate: see `coerce_or_pass_through/3`). *However*,
    `EntityData.update/3` → `EntityData.changeset/2` runs its own,
    unconditional required-field check across the **entire** entity on
    every single save, independent of `FormBuilder` and deliberately left
    untouched here — relaxing it would also affect the admin `DataForm`
    and the public entity form, which both rely on it staying strict. In
    practice: for an entity with required fields, an autosave attempt
    while any required field is still empty logs an error and keeps the
    previous `record` unpersisted, exactly like any other save rejection;
    filling in the last required field then persists everything typed
    before it in one shot (thanks to merging over `record.data`). Entities
    with no required fields autosave incrementally with no such gap.
    Checking whether a record is "complete enough" to submit is the
    parent's responsibility either way.

  ## Usage

      <.live_component
        module={PhoenixKitEntities.Components.LiveDataForm}
        id={"survey-" <> record.uuid}
        record={record}
        mode={:edit}
        lang="et"
        actor={@current_user}
        submit_label={gettext("Kinnitan")}
      />

  ## Attributes

  - `record` (required) — the `%PhoenixKitEntities.EntityData{}` being
    displayed or edited. Preload its `:entity` association before passing
    it in — that's what keeps this component DB-free to render; see
    "The host LiveView owns" above.
  - `mode` (required) — `:edit` renders a live, autosaving form; `:readonly`
    renders static "label: value" output with no inputs.
  - `lang` (optional, defaults to `nil` — safe to omit entirely) — locale
    passed straight through to `PhoenixKitEntities.FormBuilder.build_fields/3`
    as `lang_code` (and to entity loading, when the entity isn't already
    preloaded).
  - `actor` (optional, defaults to `nil` — safe to omit entirely) — the
    acting user (a struct with a `:uuid` field) or `nil`. Threaded through
    to `EntityData.update/3` as `actor_uuid:` for activity logging.
  - `submit_label` (optional, defaults to `nil` — safe to omit entirely) —
    `nil` hides the submit button entirely; any other string renders it
    as the button's text.

  ## Messages sent to the parent

  - `{:live_data_form, :saved, updated_record}` — after a successful
    autosave (fired on every change, debounced 500ms).
  - `{:live_data_form, :submitted, updated_record}` — after the submit
    button is pressed. Submit persists the params `phx-submit` just sent
    (the same merge-over-`record.data` path as autosave, so the last
    edit is never lost to the debounce window) and only sends this
    message once that save succeeds — `updated_record` reflects it. The
    component never changes `status` itself — the parent decides what
    "submitted" means for its workflow.

  On a failed save (autosave or submit) the component logs the error and
  keeps the previous `record` — it never crashes the LiveView, and on a
  failed submit specifically it does not send `:submitted` (the parent
  must not treat unpersisted data as agreed-upon).
  """

  use PhoenixKitWeb, :live_component

  require Logger

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.FormBuilder

  @impl true
  def update(assigns, socket) do
    entity = resolve_entity(assigns.record, assigns[:lang], socket)

    socket =
      socket
      |> assign(assigns)
      # `record` and `mode` are required — omitting them is a caller bug,
      # and should crash. `lang`/`actor`/`submit_label` are documented as
      # optional (safe to omit entirely, not just pass as explicit nil);
      # without these defaults, an omitted key stays absent from
      # `socket.assigns` (`assign/2` only sets keys actually present in
      # `assigns`) and `render/1`'s `@lang`/`@submit_label` raise `KeyError`.
      |> assign_new(:lang, fn -> nil end)
      |> assign_new(:actor, fn -> nil end)
      |> assign_new(:submit_label, fn -> nil end)
      |> assign(:entity, entity)
      |> assign_form()

    {:ok, socket}
  end

  # Reuses the preloaded association when the caller already loaded it,
  # falls back to the cached assign from a previous `update/2` for the
  # same entity (autosave re-renders shouldn't re-query every keystroke),
  # and only hits the database as a last resort.
  defp resolve_entity(%EntityData{entity_uuid: entity_uuid} = record, lang, socket) do
    cond do
      Ecto.assoc_loaded?(record.entity) ->
        record.entity

      match?(%{entity: %{uuid: ^entity_uuid}}, socket.assigns) ->
        socket.assigns.entity

      true ->
        Entities.get_entity!(entity_uuid, lang: lang)
    end
  end

  # Deliberately NOT `EntityData.change/2` — that goes through the full
  # `changeset/2` (entity lookup, rich-text sanitization, cross-field
  # validation), all of which hit the database. This component only needs
  # a display/param-shape changeset, so a bare structural changeset is
  # enough and keeps rendering (and `:readonly` mode entirely) DB-free.
  defp assign_form(socket) do
    changeset = Ecto.Changeset.change(socket.assigns.record)
    assign(socket, :form, to_form(changeset, as: :phoenix_kit_entity_data))
  end

  @impl true
  def handle_event("autosave", %{"phoenix_kit_entity_data" => data_params}, socket) do
    {:noreply, do_autosave(socket, Map.get(data_params, "data", %{}))}
  end

  # Mirrors the "submit" fallback clause below rather than no-op'ing: a
  # `phx-change` from a form where every input is an unticked checkbox (or
  # a checkbox group plus only `heading` fields) submits no
  # `"phoenix_kit_entity_data"` key at all — there's nothing else in the
  # payload to carry it. Treating that as "nothing changed" would silently
  # ignore exactly the case `normalize_absent_checkboxes/2` exists to
  # handle (unticking the last box). An empty map still flows through the
  # same merge/coercion/persist path as any other autosave.
  def handle_event("autosave", _params, socket), do: {:noreply, do_autosave(socket, %{})}

  # Submit persists the params `phx-submit` just sent — the same
  # merge-over-`record.data` path as autosave — rather than trusting
  # whatever autosave last managed to save. `phx-submit` carries the
  # form's full, current values regardless of the 500ms debounce window,
  # so pressing Submit means "the client agreed to exactly this state";
  # relying solely on a possibly-still-pending autosave would risk
  # silently dropping the last edit. Only sends `:submitted` — and only
  # the freshly-updated record — on a successful save; a failed save
  # logs and does not notify the parent, since it must not treat
  # unpersisted data as agreed-upon.
  def handle_event("submit", %{"phoenix_kit_entity_data" => data_params}, socket) do
    {:noreply, do_submit(socket, Map.get(data_params, "data", %{}))}
  end

  def handle_event("submit", _params, socket), do: {:noreply, do_submit(socket, %{})}

  # Merges the submitted field values over the record's existing (flat)
  # data map and persists them, preserving `status` untouched. Never
  # raises on failure — logs and keeps the previous `record` so the form
  # stays usable.
  defp do_autosave(socket, raw_data_params) do
    case persist_data(socket, raw_data_params, "autosave") do
      {:ok, updated_record} ->
        send(self(), {:live_data_form, :saved, updated_record})

        socket
        |> assign(:record, updated_record)
        |> assign_form()

      :error ->
        socket
    end
  end

  defp do_submit(socket, raw_data_params) do
    case persist_data(socket, raw_data_params, "submit") do
      {:ok, updated_record} ->
        send(self(), {:live_data_form, :submitted, updated_record})

        socket
        |> assign(:record, updated_record)
        |> assign_form()

      :error ->
        socket
    end
  end

  defp persist_data(socket, raw_data_params, log_context) do
    entity = socket.assigns.entity
    record = socket.assigns.record
    fields_definition = entity.fields_definition || []

    merged_data =
      fields_definition
      |> normalize_absent_checkboxes(raw_data_params)
      |> then(&FormBuilder.merge_other_params(fields_definition, &1))
      |> then(&Map.merge(record.data || %{}, &1))

    data_to_persist = coerce_or_pass_through(entity, merged_data, log_context)

    case EntityData.update(record, %{"data" => data_to_persist}, actor_opts(socket)) do
      {:ok, updated_record} ->
        {:ok, updated_record}

      {:error, changeset} ->
        Logger.error(
          "LiveDataForm #{log_context} failed: #{inspect(changeset.errors)} " <>
            "(entity_uuid=#{inspect(entity.uuid)} record_uuid=#{inspect(record.uuid)})"
        )

        :error
    end
  end

  # `FormBuilder.validate_data/3` runs here WITHOUT `lang_code` — even
  # though `lang` is available on the socket — deliberately, not as an
  # oversight. Passing a non-nil `lang_code` that happens to differ from
  # `Multilang.primary_language/0` routes into `validate_data/3`'s
  # secondary-language branch, which treats the payload as translation
  # overrides and skips EVERY required-field check entirely. This
  # component's `record.data` is a flat, non-multilang map — there is no
  # "secondary language" for it — so always validating as the full/primary
  # path is the only correct choice; threading `lang` through here would
  # silently reopen exactly the required-field hole this call exists to
  # help close.
  #
  # Used for type coercion (e.g. number strings -> floats, URL
  # normalization) on a best-effort basis — never as a hard gate. Errors
  # (including a still-incomplete required field) are logged and merged
  # data is persisted as-is: `validate_data/3` validates the ENTIRE
  # entity on every call, so treating its errors as blocking would mean a
  # multi-field survey never saves ANY progress until every required
  # field is filled — defeating incremental autosave of a draft. The
  # final arbiter of what actually lands in the database is
  # `EntityData.changeset/2` inside `EntityData.update/3` above; a
  # rejection there still logs and keeps the previous `record`.
  defp coerce_or_pass_through(entity, merged_data, log_context) do
    case FormBuilder.validate_data(entity, merged_data) do
      {:ok, validated_data} ->
        # `validate_data/2` returns one entry per NON-heading field on the
        # entity, including fields never touched (as `nil`) — restricting
        # to keys already present in `merged_data` before merging avoids
        # writing brand-new explicit `null`s for fields nobody has filled
        # in yet, which would otherwise break a `Map.has_key?/2` "is this
        # field answered" check on the read side. Keys already present
        # (touched, even if previously "") still get their coerced value;
        # legacy keys outside the current `fields_definition` are
        # untouched either way since they never appear in `validated_data`.
        validated_data
        |> Map.take(Map.keys(merged_data))
        |> then(&Map.merge(merged_data, &1))

      {:error, errors} ->
        Logger.warning(
          "LiveDataForm #{log_context} data failed FormBuilder validation (persisting as-is): " <>
            "#{inspect(errors)} (entity_uuid=#{inspect(entity.uuid)})"
        )

        merged_data
    end
  end

  # A checkbox group with every box unticked submits no `[key][]` param at
  # all (browsers omit unchecked checkboxes; unlike `boolean`, `checkbox`
  # fields have no hidden fallback input) — without this, "uncheck
  # everything" would silently no-op against the shallow merge below
  # instead of clearing the field.
  defp normalize_absent_checkboxes(fields_definition, params) do
    Enum.reduce(fields_definition, params, fn
      %{"type" => "checkbox", "key" => key}, acc -> Map.put_new(acc, key, [])
      _field, acc -> acc
    end)
  end

  defp actor_opts(socket) do
    case socket.assigns[:actor] do
      %{uuid: uuid} when is_binary(uuid) -> [actor_uuid: uuid]
      _ -> []
    end
  end

  @impl true
  def render(%{mode: :readonly} = assigns) do
    ~H"""
    <div class="space-y-4">
      <%= for field <- @entity.fields_definition || [] do %>
        {readonly_field(field, @record.data || %{})}
      <% end %>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <.form
        for={@form}
        phx-change="autosave"
        phx-submit="submit"
        phx-debounce="500"
        phx-target={@myself}
        class="space-y-6"
      >
        {FormBuilder.build_fields(@entity, @form,
          wrapper_class: "mb-4",
          lang_code: @lang,
          id_prefix: @record.uuid
        )}

        <%= if @submit_label do %>
          <div class="flex justify-end">
            <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Saving…")}>
              {@submit_label}
            </button>
          </div>
        <% end %>
      </.form>
    </div>
    """
  end

  # ── Readonly field rendering ─────────────────────────────────

  defp readonly_field(%{"type" => "heading"} = field, _data) do
    assigns = %{field: field}

    ~H"""
    <h3 class="text-base font-semibold border-b border-base-300 pb-1 mt-6 mb-2">
      {@field["label"]}
    </h3>
    """
  end

  defp readonly_field(%{"type" => "checkbox"} = field, data) do
    assigns = %{field: field, display: readonly_list(Map.get(data, field["key"]))}

    ~H"""
    <div>
      <span class="font-semibold">{@field["label"]}:</span>
      <span>{@display}</span>
    </div>
    """
  end

  defp readonly_field(%{"type" => "textarea"} = field, data) do
    assigns = %{field: field, display: readonly_text(Map.get(data, field["key"]))}

    ~H"""
    <div>
      <div class="font-semibold">{@field["label"]}</div>
      <div class="whitespace-pre-wrap">{@display}</div>
    </div>
    """
  end

  defp readonly_field(%{"type" => "boolean"} = field, data) do
    assigns = %{field: field, display: readonly_boolean(Map.get(data, field["key"]))}

    ~H"""
    <div>
      <span class="font-semibold">{@field["label"]}:</span>
      <span>{@display}</span>
    </div>
    """
  end

  defp readonly_field(field, data) do
    assigns = %{field: field, display: readonly_value(Map.get(data, field["key"]))}

    ~H"""
    <div>
      <span class="font-semibold">{@field["label"]}:</span>
      <span>{@display}</span>
    </div>
    """
  end

  defp readonly_list(nil), do: dash()
  defp readonly_list([]), do: dash()
  defp readonly_list(values) when is_list(values), do: Enum.join(values, ", ")
  defp readonly_list(_), do: dash()

  defp readonly_text(nil), do: dash()
  defp readonly_text(""), do: dash()
  defp readonly_text(value) when is_binary(value), do: value
  defp readonly_text(value), do: to_string(value)

  defp readonly_boolean(nil), do: dash()
  defp readonly_boolean(value) when value in [true, "true", "1", 1], do: gettext("Yes")
  defp readonly_boolean(_value), do: gettext("No")

  defp readonly_value(nil), do: dash()
  defp readonly_value(""), do: dash()
  defp readonly_value(value) when is_list(value), do: readonly_list(value)
  defp readonly_value(value) when is_binary(value), do: value
  defp readonly_value(value), do: to_string(value)

  defp dash, do: gettext("—")
end
