defmodule PhoenixKitEntities.Web.DataForm do
  @moduledoc """
  LiveView for creating and editing entity data records.
  Provides dynamic form interface based on entity schema definition.
  """

  use PhoenixKitWeb, :live_view
  on_mount(PhoenixKitEntities.Web.Hooks)

  import PhoenixKitWeb.Components.MultilangForm

  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Multilang
  alias PhoenixKit.Utils.Routes
  alias PhoenixKit.Utils.Slug
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.Events
  alias PhoenixKitEntities.FormBuilder
  alias PhoenixKitEntities.Presence
  alias PhoenixKitEntities.PresenceHelpers

  # Fields that should keep their primary-language DB column value on secondary tabs.
  @preserve_fields %{"title" => :title, "slug" => :slug, "status" => :status}

  @impl true
  def mount(%{"entity_slug" => entity_slug, "uuid" => uuid} = params, _session, socket) do
    # Set locale for LiveView process
    locale =
      params["locale"] || socket.assigns[:current_locale]

    # Edit mode with slug
    entity = Entities.get_entity_by_name(entity_slug, lang: locale)
    data_record = EntityData.get!(uuid, lang: locale)
    changeset = EntityData.change(data_record)

    mount_data_form(socket, entity, data_record, changeset, gettext("Edit Data"), locale)
  end

  def mount(%{"entity_id" => entity_uuid, "id" => id} = params, _session, socket) do
    # Set locale for LiveView process
    locale =
      params["locale"] || socket.assigns[:current_locale]

    # Edit mode with ID (backwards compat)
    entity = Entities.get_entity!(entity_uuid, lang: locale)
    data_record = EntityData.get!(id, lang: locale)
    changeset = EntityData.change(data_record)

    mount_data_form(socket, entity, data_record, changeset, gettext("Edit Data"), locale)
  end

  def mount(%{"entity_slug" => entity_slug} = params, _session, socket) do
    # Set locale for LiveView process
    locale =
      params["locale"] || socket.assigns[:current_locale]

    # Create mode with slug
    entity = Entities.get_entity_by_name(entity_slug, lang: locale)
    data_record = %EntityData{entity_uuid: entity.uuid}
    changeset = EntityData.change(data_record)

    mount_data_form(socket, entity, data_record, changeset, gettext("New Data"), locale)
  end

  def mount(%{"entity_id" => entity_uuid} = params, _session, socket) do
    # Set locale for LiveView process
    locale =
      params["locale"] || socket.assigns[:current_locale]

    # Create mode with ID (backwards compat)
    entity = Entities.get_entity!(entity_uuid, lang: locale)
    data_record = %EntityData{entity_uuid: entity.uuid}
    changeset = EntityData.change(data_record)

    mount_data_form(socket, entity, data_record, changeset, gettext("New Data"), locale)
  end

  defp mount_data_form(socket, entity, data_record, changeset, page_title, locale) do
    project_title = Settings.get_project_title()
    current_user = socket.assigns[:phoenix_kit_current_user]

    # For new records, set default status to "published" to avoid validation errors
    changeset =
      if is_nil(data_record.uuid) do
        Ecto.Changeset.put_change(changeset, :status, "published")
      else
        changeset
      end

    form_record_key =
      case data_record.uuid do
        nil -> {:new, entity.name}
        uuid -> uuid
      end

    live_source = ensure_live_source(socket)

    # Multilang state (driven by Languages module globally)
    multilang_enabled = multilang_enabled?()

    # Lazy re-key: if global primary changed since this record was saved,
    # restructure data around the new primary language.
    # Also seed _title into JSONB data for backwards compat.
    changeset =
      if multilang_enabled and data_record.uuid do
        changeset
        |> rekey_data_on_mount()
        |> seed_translatable_fields(data_record)
      else
        changeset
      end

    socket =
      socket
      |> assign(:current_locale, locale)
      |> assign(:page_title, page_title)
      |> assign(:project_title, project_title)
      |> assign(:entity, entity)
      |> assign(:data_record, data_record)
      |> assign(:changeset, changeset)
      |> assign(:current_user, current_user)
      |> assign(:form_record_key, form_record_key)
      |> assign(:form_record_topic_key, normalize_record_key(form_record_key))
      |> assign(:live_source, live_source)
      |> assign(:has_unsaved_changes, false)
      |> mount_multilang()

    socket = mount_data_presence(socket, entity, data_record, form_record_key, current_user)

    {:ok, socket}
  end

  defp mount_data_presence(socket, entity, data_record, form_record_key, current_user) do
    if connected?(socket) do
      Events.subscribe_to_entity_data(entity.uuid)
      Events.subscribe_to_data_form(entity.uuid, form_record_key)
      setup_data_editing(socket, data_record, current_user)
    else
      assign_no_lock(socket)
    end
  end

  defp setup_data_editing(socket, data_record, current_user) do
    if data_record.uuid do
      {:ok, _ref} =
        PresenceHelpers.track_editing_session(:data, data_record.uuid, socket, current_user)

      PresenceHelpers.subscribe_to_editing(:data, data_record.uuid)
      socket = assign_editing_role(socket, data_record.uuid)

      if socket.assigns.readonly?,
        do: load_spectator_state(socket, data_record.uuid),
        else: socket
    else
      assign_no_lock(socket)
    end
  end

  defp assign_no_lock(socket) do
    socket
    |> assign(:lock_owner?, true)
    |> assign(:readonly?, false)
    |> assign(:lock_owner_user, nil)
    |> assign(:spectators, [])
  end

  defp assign_editing_role(socket, data_uuid) do
    current_user = socket.assigns[:current_user]

    case PresenceHelpers.get_editing_role(:data, data_uuid, socket.id, current_user.uuid) do
      {:owner, _presences} ->
        # I'm the owner - I can edit (or same user in different tab)
        socket
        |> assign(:lock_owner?, true)
        |> assign(:readonly?, false)
        |> populate_presence_info(:data, data_uuid)

      {:spectator, _owner_meta, _presences} ->
        # Different user is the owner - I'm read-only
        socket
        |> assign(:lock_owner?, false)
        |> assign(:readonly?, true)
        |> populate_presence_info(:data, data_uuid)
    end
  end

  defp load_spectator_state(socket, data_uuid) do
    # Owner might have unsaved changes - sync from their Presence metadata
    case PresenceHelpers.get_lock_owner(:data, data_uuid) do
      %{form_state: form_state} when not is_nil(form_state) ->
        # Apply owner's form state
        params = Map.get(form_state, :params) || Map.get(form_state, "params")

        if params do
          socket
          |> apply_remote_data_params(params)
          |> assign(:has_unsaved_changes, true)
        else
          socket
        end

      _ ->
        # No form state to sync
        socket
    end
  end

  @impl true
  def terminate(_reason, _socket) do
    :ok
  end

  @impl true
  def handle_event("switch_language", %{"lang" => lang_code}, socket) do
    {:noreply, handle_switch_language(socket, lang_code)}
  end

  def handle_event("validate", %{"phoenix_kit_entity_data" => data_params}, socket) do
    if socket.assigns[:lock_owner?] do
      do_validate(data_params, socket)
    else
      # Spectator - ignore local changes, wait for broadcasts
      {:noreply, socket}
    end
  rescue
    e ->
      require Logger

      Logger.error(
        "Entity data validate failed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:noreply, put_flash(socket, :error, gettext("Validation error — your data is preserved."))}
  end

  def handle_event("save", %{"phoenix_kit_entity_data" => data_params}, socket) do
    if socket.assigns[:lock_owner?] do
      do_save(data_params, socket)
    else
      {:noreply, put_flash(socket, :error, gettext("Cannot save - you are spectating"))}
    end
  rescue
    e ->
      require Logger

      Logger.error(
        "Entity data save failed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
      )

      {:noreply, put_flash(socket, :error, gettext("Something went wrong. Please try again."))}
  end

  def handle_event("reset", _params, socket) do
    if socket.assigns[:lock_owner?] do
      # Reload data record from database or reset to empty state
      {data_record, changeset} =
        if socket.assigns.data_record.uuid do
          # Reload from database
          reloaded_data = EntityData.get_data!(socket.assigns.data_record.uuid)
          {reloaded_data, EntityData.change(reloaded_data)}
        else
          # Reset to empty new data record
          empty_data = %EntityData{
            entity_uuid: socket.assigns.entity.uuid
          }

          changeset =
            empty_data
            |> EntityData.change()
            |> Ecto.Changeset.put_change(:status, "published")

          {empty_data, changeset}
        end

      socket =
        socket
        |> assign(:data_record, data_record)
        |> assign(:changeset, changeset)
        |> put_flash(:info, gettext("Changes reset to last saved state"))
        |> broadcast_data_form_state(extract_changeset_params(changeset))

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, gettext("Cannot reset - you are spectating"))}
    end
  end

  def handle_event("generate_slug", _params, socket) do
    if socket.assigns[:lock_owner?] do
      do_generate_slug(socket)
    else
      {:noreply, socket}
    end
  end

  # ── Validate/Save helpers (below all handle_event clauses to avoid grouping warnings) ──

  defp maybe_auto_generate_data_slug(data_params, _entity_uuid, record_uuid, _socket)
       when not is_nil(record_uuid),
       do: data_params

  defp maybe_auto_generate_data_slug(data_params, entity_uuid, record_uuid, socket) do
    current_data = Ecto.Changeset.apply_changes(socket.assigns.changeset)
    previous_title = current_data.title || ""
    title = data_params["title"] || previous_title
    current_slug = data_params["slug"] || ""
    auto_generated_slug = auto_generate_entity_slug(entity_uuid, record_uuid, previous_title)

    if current_slug == "" || current_slug == auto_generated_slug do
      Map.put(data_params, "slug", auto_generate_entity_slug(entity_uuid, record_uuid, title))
    else
      data_params
    end
  end

  defp do_validate(data_params, socket) do
    entity_uuid = socket.assigns.entity.uuid
    record_uuid = socket.assigns.data_record.uuid
    form_data = Map.get(data_params, "data", %{})

    data_params =
      if socket.assigns.data_record.uuid,
        do: data_params,
        else: Map.put(data_params, "created_by_uuid", socket.assigns.current_user.uuid)

    data_params =
      maybe_auto_generate_data_slug(data_params, entity_uuid, record_uuid, socket)

    current_lang = socket.assigns[:current_lang]

    # Inject _title and _slug into form data so they flow through multilang merge
    form_data =
      form_data
      |> inject_db_field_into_data("title", data_params, current_lang, socket.assigns)
      |> inject_db_field_into_data("slug", data_params, current_lang, socket.assigns)

    # On secondary language tabs, preserve primary-language fields that aren't in the form
    data_params =
      preserve_primary_fields(
        data_params,
        socket.assigns.changeset,
        socket.assigns,
        @preserve_fields
      )

    case FormBuilder.validate_data(socket.assigns.entity, form_data, current_lang) do
      {:ok, validated_data} ->
        validated_data =
          validated_data
          |> inject_db_field_into_data("title", data_params, current_lang, socket.assigns)
          |> inject_db_field_into_data("slug", data_params, current_lang, socket.assigns)

        data_params = strip_lang_params(data_params)

        final_data =
          merge_multilang_data(
            socket.assigns.changeset,
            current_lang,
            validated_data,
            socket.assigns
          )

        params = Map.put(data_params, "data", final_data)

        changeset =
          socket.assigns.data_record
          |> EntityData.change(params)
          |> Map.put(:action, :validate)

        socket =
          socket
          |> assign(:changeset, changeset)
          |> broadcast_data_form_state(params)

        {:noreply, socket}

      {:error, errors} ->
        # Preserve full multilang data in both changeset and broadcast
        error_data =
          merge_multilang_data(
            socket.assigns.changeset,
            current_lang,
            form_data,
            socket.assigns
          )

        data_params =
          data_params
          |> Map.delete("lang_title")
          |> Map.delete("lang_slug")

        error_params = Map.put(data_params, "data", error_data)

        changeset =
          socket.assigns.data_record
          |> EntityData.change(error_params)
          |> add_form_errors(errors)
          |> Map.put(:action, :validate)

        socket =
          socket
          |> assign(:changeset, changeset)
          |> broadcast_data_form_state(error_params)

        {:noreply, socket}
    end
  end

  defp do_save(data_params, socket) do
    # Extract the data field from params
    form_data = Map.get(data_params, "data", %{})

    current_lang = socket.assigns[:current_lang]

    # Inject _title and _slug into form data so they flow through multilang merge
    form_data =
      form_data
      |> inject_db_field_into_data("title", data_params, current_lang, socket.assigns)
      |> inject_db_field_into_data("slug", data_params, current_lang, socket.assigns)

    # On secondary language tabs, preserve primary-language fields that aren't in the form
    data_params =
      preserve_primary_fields(
        data_params,
        socket.assigns.changeset,
        socket.assigns,
        @preserve_fields
      )

    # Validate the form data against entity field definitions
    case FormBuilder.validate_data(socket.assigns.entity, form_data, current_lang) do
      {:ok, validated_data} ->
        validated_data =
          validated_data
          |> inject_db_field_into_data("title", data_params, current_lang, socket.assigns)
          |> inject_db_field_into_data("slug", data_params, current_lang, socket.assigns)

        data_params = strip_lang_params(data_params)

        final_data =
          merge_multilang_data(
            socket.assigns.changeset,
            current_lang,
            validated_data,
            socket.assigns
          )

        # Add metadata to params
        params =
          data_params
          |> Map.put("data", final_data)
          |> maybe_add_creator_uuid(socket.assigns.current_user, socket.assigns.data_record)

        case save_data_record(socket, params) do
          {:ok, saved_record} ->
            {:noreply, handle_data_save_success(socket, saved_record, params)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket |> assign(:changeset, changeset) |> broadcast_data_form_state(params)}
        end

      {:error, errors} ->
        # Preserve full multilang data in both changeset and broadcast
        error_data =
          merge_multilang_data(
            socket.assigns.changeset,
            current_lang,
            form_data,
            socket.assigns
          )

        data_params =
          data_params
          |> Map.delete("lang_title")
          |> Map.delete("lang_slug")

        error_params = Map.put(data_params, "data", error_data)

        changeset =
          socket.assigns.data_record
          |> EntityData.change(error_params)
          |> add_form_errors(errors)

        error_list =
          Enum.map_join(errors, "; ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        socket =
          socket
          |> assign(:changeset, changeset)
          |> put_flash(
            :error,
            gettext("Field validation errors: %{errors}", errors: error_list)
          )
          |> broadcast_data_form_state(error_params)

        {:noreply, socket}
    end
  end

  defp handle_data_save_success(socket, saved_record, params) do
    if socket.assigns.data_record.uuid do
      changeset = EntityData.change(saved_record)

      socket
      |> assign(:data_record, saved_record)
      |> assign(:changeset, changeset)
      |> put_flash(:info, gettext("Data record saved successfully"))
      |> broadcast_data_form_state(params)
    else
      entity_name = socket.assigns.entity.name

      socket
      |> put_flash(:info, gettext("Data record created successfully"))
      |> push_navigate(
        to:
          Routes.path(
            "/admin/entities/#{entity_name}/data/#{saved_record.uuid}/edit",
            locale: socket.assigns.current_locale_base
          )
      )
    end
  end

  ## Live updates

  @impl true
  def handle_info({:data_form_change, entity_uuid, record_key, payload, source}, socket) do
    cond do
      source == socket.assigns.live_source ->
        {:noreply, socket}

      entity_uuid != socket.assigns.entity.uuid ->
        {:noreply, socket}

      normalize_record_key(record_key) != socket.assigns.form_record_topic_key ->
        {:noreply, socket}

      true ->
        params = Map.get(payload, :params) || Map.get(payload, "params") || %{}

        socket =
          socket
          |> apply_remote_data_params(params)

        {:noreply, socket}
    end
  end

  def handle_info({:data_updated, entity_uuid, data_uuid}, socket) do
    cond do
      entity_uuid != socket.assigns.entity.uuid ->
        {:noreply, socket}

      socket.assigns.data_record.uuid != data_uuid ->
        {:noreply, socket}

      # Ignore our own saves — the save handler already refreshes state
      socket.assigns[:lock_owner?] ->
        {:noreply, socket}

      true ->
        locale = socket.assigns[:current_locale]
        data_record = EntityData.get_data!(data_uuid, lang: locale)
        changeset = EntityData.change(data_record)

        socket =
          socket
          |> assign(:data_record, data_record)
          |> assign(:form_record_key, data_record.uuid)
          |> assign(:form_record_topic_key, normalize_record_key(data_record.uuid))
          |> assign(:changeset, changeset)
          |> put_flash(
            :info,
            gettext("Record updated in another session. Showing latest changes.")
          )

        {:noreply, socket}
    end
  end

  def handle_info({:data_deleted, entity_uuid, data_uuid}, socket) do
    cond do
      entity_uuid != socket.assigns.entity.uuid ->
        {:noreply, socket}

      socket.assigns.data_record.uuid != data_uuid ->
        {:noreply, socket}

      true ->
        socket =
          socket
          |> put_flash(:error, gettext("This record was removed in another session."))
          |> push_navigate(
            to:
              Routes.path("/admin/entities/#{socket.assigns.entity.name}/data",
                locale: socket.assigns.current_locale_base
              )
          )

        {:noreply, socket}
    end
  end

  def handle_info({:entity_created, _}, socket), do: {:noreply, socket}

  def handle_info({:entity_updated, entity_uuid}, socket) do
    if entity_uuid == socket.assigns.entity.uuid do
      locale = socket.assigns[:current_locale]
      entity = Entities.get_entity!(entity_uuid, lang: locale)

      # If entity was archived or unpublished, redirect to entities list
      if entity.status != "published" do
        {:noreply,
         socket
         |> put_flash(
           :warning,
           gettext("Entity '%{name}' was %{status} in another session.",
             name: entity.display_name,
             status: entity.status
           )
         )
         |> redirect(
           to: Routes.path("/admin/entities", locale: socket.assigns.current_locale_base)
         )}
      else
        socket =
          socket
          |> refresh_entity_assignment(entity)
          |> put_flash(:info, gettext("Entity schema updated. Form revalidated."))

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:entity_deleted, entity_uuid}, socket) do
    if entity_uuid == socket.assigns.entity.uuid do
      socket =
        socket
        |> put_flash(:error, gettext("Entity was deleted in another session."))
        |> push_navigate(
          to: Routes.path("/admin/entities", locale: socket.assigns.current_locale_base)
        )

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Someone joined or left - check if our role changed
    if socket.assigns.data_record && socket.assigns.data_record.uuid do
      data_uuid = socket.assigns.data_record.uuid
      was_owner = socket.assigns[:lock_owner?]

      # Re-evaluate our role
      socket = assign_editing_role(socket, data_uuid)

      # If we were promoted from spectator to owner, reload fresh data
      if !was_owner && socket.assigns[:lock_owner?] do
        data_record = EntityData.get_data!(data_uuid)

        socket
        |> assign(:data_record, data_record)
        |> assign(:changeset, EntityData.change(data_record))
        |> assign(:has_unsaved_changes, false)
        |> then(&{:noreply, &1})
      else
        # Just a presence update (someone joined/left as spectator)
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Catch-all — ignore unexpected messages rather than crashing the socket.
  def handle_info(_message, socket), do: {:noreply, socket}

  # Strip lang_title/lang_slug from params — these are translation input names
  # that shouldn't be passed to the changeset as DB fields.
  defp strip_lang_params(params) do
    params
    |> Map.delete("lang_title")
    |> Map.delete("lang_slug")
  end

  # ── Lazy re-keying helpers (primary language change) ────────

  # Re-keys JSONB data in changeset if embedded primary != global primary.
  defp rekey_data_on_mount(changeset) do
    current_data = Ecto.Changeset.get_field(changeset, :data)
    rekeyed = Multilang.maybe_rekey_data(current_data)

    if rekeyed != current_data do
      Ecto.Changeset.put_change(changeset, :data, rekeyed)
    else
      changeset
    end
  end

  # Seeds `_title` and `_slug` into the JSONB data column for existing records on mount.
  # Handles backwards compat: migrates from metadata["translations"] to data[lang]["_title"].
  defp seed_translatable_fields(changeset, data_record) do
    data = Ecto.Changeset.get_field(changeset, :data) || %{}

    if Multilang.multilang_data?(data) do
      primary = data["_primary_language"]
      primary_data = Map.get(data, primary, %{})

      changeset =
        if Map.has_key?(primary_data, "_title") do
          changeset
        else
          title = Ecto.Changeset.get_field(changeset, :title)
          do_seed_title(changeset, data, data_record, primary, primary_data, title)
        end

      # Also seed _slug if not already present
      seed_slug_in_data(changeset)
    else
      changeset
    end
  end

  defp seed_slug_in_data(changeset) do
    data = Ecto.Changeset.get_field(changeset, :data) || %{}
    primary = data["_primary_language"]
    primary_data = Map.get(data, primary, %{})

    if Map.has_key?(primary_data, "_slug") do
      changeset
    else
      slug = Ecto.Changeset.get_field(changeset, :slug)

      if is_binary(slug) and slug != "" do
        updated_primary = Map.put(primary_data, "_slug", slug)
        data = Map.put(data, primary, updated_primary)
        Ecto.Changeset.put_change(changeset, :data, data)
      else
        changeset
      end
    end
  end

  defp do_seed_title(changeset, data, data_record, primary, primary_data, title) do
    # Seed primary _title from the title column
    updated_primary = Map.put(primary_data, "_title", title || "")
    data = Map.put(data, primary, updated_primary)

    # Migrate secondary titles from metadata["translations"]
    metadata = Ecto.Changeset.get_field(changeset, :metadata) || %{}
    {data, metadata} = migrate_title_translations(data, metadata, title)

    changeset = Ecto.Changeset.put_change(changeset, :data, data)

    # Update title column if primary was rekeyed
    changeset = maybe_sync_rekeyed_title(changeset, data, data_record, primary, title)

    if metadata != (Ecto.Changeset.get_field(changeset, :metadata) || %{}) do
      Ecto.Changeset.put_change(changeset, :metadata, metadata)
    else
      changeset
    end
  end

  defp migrate_title_translations(data, metadata, primary_title) do
    translations = metadata["translations"] || %{}

    Enum.reduce(translations, {data, metadata}, fn
      {lang_code, %{"title" => lang_title}}, {d, m}
      when is_binary(lang_title) and lang_title != "" ->
        d = put_secondary_title(d, lang_code, lang_title, primary_title)
        m = clean_title_translation(m, lang_code)
        {d, m}

      _, acc ->
        acc
    end)
  end

  defp put_secondary_title(data, _lang_code, lang_title, primary_title)
       when lang_title == primary_title,
       do: data

  defp put_secondary_title(data, lang_code, lang_title, _primary_title) do
    lang_data = Map.get(data, lang_code, %{})
    Map.put(data, lang_code, Map.put(lang_data, "_title", lang_title))
  end

  defp clean_title_translation(metadata, lang_code) do
    cleaned = metadata |> Map.get("translations", %{}) |> Map.delete(lang_code)

    if map_size(cleaned) == 0,
      do: Map.delete(metadata, "translations"),
      else: Map.put(metadata, "translations", cleaned)
  end

  defp maybe_sync_rekeyed_title(changeset, data, data_record, primary, title) do
    old_embedded = get_in(data_record.data || %{}, ["_primary_language"])

    if old_embedded && old_embedded != primary do
      new_title = get_in(data, [primary, "_title"])

      if is_binary(new_title) and new_title != "" and new_title != title do
        Ecto.Changeset.put_change(changeset, :title, new_title)
      else
        changeset
      end
    else
      changeset
    end
  end

  # Helper Functions

  defp do_generate_slug(socket) do
    changeset = socket.assigns.changeset
    current_lang = socket.assigns[:current_lang]
    primary = socket.assigns[:primary_language]
    is_secondary = socket.assigns[:multilang_enabled] && current_lang != primary
    title = slug_source_title(changeset, is_secondary, current_lang)

    if title == "" do
      {:noreply, socket}
    else
      {params, changeset} = build_slug_params(socket, title, is_secondary, current_lang)

      socket =
        socket
        |> assign(:changeset, changeset)
        |> broadcast_data_form_state(params)

      {:noreply, socket}
    end
  end

  defp slug_source_title(changeset, true = _secondary, current_lang) do
    data = Ecto.Changeset.get_field(changeset, :data) || %{}

    case Multilang.get_language_data(data, current_lang) do
      %{"_title" => lang_title} when is_binary(lang_title) and lang_title != "" -> lang_title
      _ -> Ecto.Changeset.get_field(changeset, :title) || ""
    end
  end

  defp slug_source_title(changeset, _primary, _current_lang) do
    Ecto.Changeset.get_field(changeset, :title) || ""
  end

  defp build_slug_params(socket, title, is_secondary, current_lang) do
    changeset = socket.assigns.changeset
    db_entity_uuid = Ecto.Changeset.get_field(changeset, :entity_uuid)
    db_title = Ecto.Changeset.get_field(changeset, :title) || ""
    status = Ecto.Changeset.get_field(changeset, :status) || "draft"
    data = Ecto.Changeset.get_field(changeset, :data) || %{}
    created_by_uuid = Ecto.Changeset.get_field(changeset, :created_by_uuid)

    {slug, data} =
      compute_slug_and_data(socket, title, is_secondary, current_lang, changeset, data)

    params = %{
      "entity_uuid" => db_entity_uuid,
      "title" => db_title,
      "slug" => slug,
      "status" => status,
      "data" => data,
      "created_by_uuid" => created_by_uuid
    }

    changeset =
      socket.assigns.data_record
      |> EntityData.change(params)
      |> Map.put(:action, :validate)

    {params, changeset}
  end

  defp compute_slug_and_data(socket, title, true = _secondary, current_lang, changeset, data) do
    entity_uuid = socket.assigns.entity.uuid
    record_uuid = socket.assigns.data_record.uuid

    slug_text =
      title
      |> Slug.slugify()
      |> Slug.ensure_unique(
        &EntityData.secondary_slug_exists?(entity_uuid, current_lang, &1, record_uuid)
      )

    lang_data = Multilang.get_raw_language_data(data, current_lang)
    updated_lang = Map.put(lang_data, "_slug", slug_text)
    updated_data = Multilang.put_language_data(data, current_lang, updated_lang)
    {Ecto.Changeset.get_field(changeset, :slug), updated_data}
  end

  defp compute_slug_and_data(socket, title, _primary, _current_lang, _changeset, data) do
    entity_uuid = socket.assigns.entity.uuid
    record_uuid = socket.assigns.data_record.uuid
    slug_text = auto_generate_entity_slug(entity_uuid, record_uuid, title)
    {slug_text, data}
  end

  defp broadcast_data_form_state(socket, params) when is_map(params) do
    socket =
      if connected?(socket) &&
           socket.assigns[:form_record_key] &&
           socket.assigns[:entity] &&
           socket.assigns.data_record.uuid &&
           socket.assigns[:lock_owner?] do
        data_uuid = socket.assigns.data_record.uuid
        topic = PresenceHelpers.editing_topic(:data, data_uuid)

        payload = %{params: params}

        # Update Presence metadata with form state (for spectators to sync)
        Presence.update(self(), topic, socket.id, fn meta ->
          Map.put(meta, :form_state, payload)
        end)

        # Also broadcast for real-time sync to spectators
        Events.broadcast_data_form_change(
          socket.assigns.entity.uuid,
          socket.assigns.form_record_key,
          payload,
          source: socket.assigns.live_source
        )

        socket
      else
        socket
      end

    # Mark that we have unsaved changes
    assign(socket, :has_unsaved_changes, true)
  end

  defp apply_remote_data_params(socket, params) when is_map(params) do
    # Build the changeset WITHOUT enforcing validations yet
    # This ensures we capture the exact remote state, even invalid values
    changeset =
      socket.assigns.data_record
      |> Ecto.Changeset.cast(params, [
        :entity_uuid,
        :title,
        :slug,
        :status,
        :data,
        :metadata,
        :created_by_uuid
      ])
      |> Map.put(:action, :validate)

    # Apply changes to get the updated record with remote values
    updated_record = Ecto.Changeset.apply_changes(changeset)

    # Now create a validated changeset for display
    # This will show validation errors but preserve the remote values
    validated_changeset = EntityData.change(updated_record)

    socket
    |> assign(:data_record, updated_record)
    |> assign(:changeset, validated_changeset)
    |> assign(:has_unsaved_changes, true)
  end

  defp refresh_entity_assignment(socket, entity) do
    params = extract_changeset_params(socket.assigns.changeset)

    data_record = %{
      socket.assigns.data_record
      | entity: entity,
        entity_uuid: entity.uuid
    }

    changeset =
      data_record
      |> EntityData.change(params)
      |> Map.put(:action, :validate)

    socket
    |> assign(:entity, entity)
    |> assign(:data_record, data_record)
    |> assign(:changeset, changeset)
    |> refresh_multilang()
  end

  defp extract_changeset_params(changeset) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.from_struct()
    |> Map.take([:entity_uuid, :title, :slug, :status, :data, :metadata, :created_by_uuid])
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp save_data_record(socket, data_params) do
    opts = actor_opts(socket)

    if socket.assigns.data_record.uuid do
      EntityData.update(socket.assigns.data_record, data_params, opts)
    else
      EntityData.create(data_params, opts)
    end
  end

  # Threads the current user UUID through to context functions that
  # accept `actor_uuid:` opts.
  defp actor_opts(socket) do
    case socket.assigns[:phoenix_kit_current_scope] do
      %{user: %{uuid: uuid}} -> [actor_uuid: uuid]
      _ -> []
    end
  end

  defp maybe_add_creator_uuid(params, current_user, data_record) do
    if data_record.uuid do
      # Editing existing record - don't change creator
      params
    else
      # Creating new record - set creator
      params
      |> Map.put("created_by_uuid", current_user.uuid)
    end
  end

  defp add_form_errors(changeset, errors) do
    Enum.reduce(errors, changeset, fn {field_key, field_errors}, acc ->
      Enum.reduce(field_errors, acc, fn error, inner_acc ->
        Ecto.Changeset.add_error(inner_acc, :data, "#{field_key}: #{error}")
      end)
    end)
  end

  defp ensure_live_source(socket) do
    socket.assigns[:live_source] ||
      (socket.id ||
         "entities-data-" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false))
  end

  defp normalize_record_key({:new, key}) when is_atom(key), do: "new-#{Atom.to_string(key)}"
  defp normalize_record_key({:new, key}) when is_binary(key), do: "new-#{key}"
  defp normalize_record_key({:new, key}), do: "new-#{to_string(key)}"
  defp normalize_record_key(key) when is_integer(key), do: Integer.to_string(key)
  defp normalize_record_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_record_key(key) when is_binary(key), do: key
  defp normalize_record_key(key), do: to_string(key)

  defp auto_generate_entity_slug(_entity_uuid, _record_uuid, title) when title in [nil, ""],
    do: ""

  defp auto_generate_entity_slug(entity_uuid, current_record_uuid, title) do
    title
    |> Slug.slugify()
    |> Slug.ensure_unique(&slug_taken_by_other?(entity_uuid, &1, current_record_uuid))
  end

  defp slug_taken_by_other?(_entity_uuid, "", _current_record_uuid), do: false

  defp slug_taken_by_other?(entity_uuid, candidate, current_record_uuid) do
    case EntityData.get_by_slug(entity_uuid, candidate) do
      nil ->
        false

      %EntityData{uuid: uuid} ->
        is_nil(current_record_uuid) || uuid != current_record_uuid
    end
  end

  defp populate_presence_info(socket, type, id) do
    # Get all presences sorted by joined_at (FIFO order)
    presences = PresenceHelpers.get_sorted_presences(type, id)

    # Extract owner (first in list) and spectators (rest of list)
    {lock_owner_user, lock_info, spectators} =
      case presences do
        [] ->
          {nil, nil, []}

        [{owner_socket_id, owner_meta} | spectator_list] ->
          # Build owner info
          lock_info = %{
            socket_id: owner_socket_id,
            user_uuid: owner_meta.user_uuid
          }

          # Map spectators to expected format
          spectators =
            Enum.map(spectator_list, fn {spectator_socket_id, meta} ->
              %{
                socket_id: spectator_socket_id,
                user: meta.user,
                user_uuid: meta.user_uuid
              }
            end)

          {owner_meta.user, lock_info, spectators}
      end

    socket
    |> assign(:lock_owner_user, lock_owner_user)
    |> assign(:lock_info, lock_info)
    |> assign(:spectators, spectators)
  end

  @impl true
  def render(assigns) do
    ~H"""
      <div class="container flex flex-col mx-auto px-4 py-6">
        <%!-- Header Section --%>
        <.admin_page_header back={
          PhoenixKit.Utils.Routes.path("/admin/entities/#{@entity.name}/data")
        }>
          <h1 class="text-xl sm:text-2xl lg:text-3xl font-bold text-base-content">
            <%= if @data_record.uuid do %>
              {gettext("Edit %{entity}", entity: @entity.display_name)}
            <% else %>
              {gettext("Create New %{entity}", entity: @entity.display_name)}
            <% end %>
          </h1>
          <p class="text-sm text-base-content/60 mt-0.5">
            <%= if @data_record.uuid do %>
              {gettext("Update data for the %{entity} entity", entity: @entity.display_name)}
            <% else %>
              {gettext("Add data for the %{entity} entity", entity: @entity.display_name)}
            <% end %>
          </p>
        </.admin_page_header>

        <%!-- Readonly Banner --%>
        <%= if @readonly? do %>
          <div class="alert alert-info mb-6">
            <.icon name="hero-eye" class="w-5 h-5" />
            <span>
              {gettext(
                "This record is currently being edited by another user. You are in view-only mode."
              )}
            </span>
          </div>
        <% end %>

        <%!-- Edit Mode Form --%>
        <.form
          :let={f}
          for={@changeset}
          phx-change="validate"
          phx-debounce="500"
          phx-submit="save"
          class="space-y-8"
        >
          <div class="flex justify-end">
            <button
              type="submit"
              class="btn btn-primary"
              disabled={@readonly?}
              phx-disable-with={gettext("Saving…")}
            >
              <%= if @data_record.uuid do %>
                {gettext("Update %{entity}", entity: @entity.display_name)}
              <% else %>
                {gettext("Create %{entity}", entity: @entity.display_name)}
              <% end %>
            </button>
          </div>

          <%= if @show_multilang_tabs do %>
            <%!-- Multilang: unified card with language tabs wrapping all content --%>
            <% lang_data = get_lang_data(@changeset, @current_lang, @multilang_enabled) %>
            <div class="card bg-base-100 shadow-xl">
              <.multilang_tabs
                multilang_enabled={@multilang_enabled}
                language_tabs={@language_tabs}
                current_lang={@current_lang}
              />

              <.multilang_fields_wrapper
                multilang_enabled={@multilang_enabled}
                current_lang={@current_lang}
              >
                <:skeleton>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div class="space-y-2">
                      <div class="skeleton h-4 w-24"></div>
                      <div class="skeleton h-12 w-full"></div>
                    </div>
                    <div class="space-y-2">
                      <div class="skeleton h-4 w-32"></div>
                      <div class="skeleton h-12 w-full"></div>
                      <div class="skeleton h-3 w-48"></div>
                    </div>
                  </div>
                  <div class="divider my-2"></div>
                  <div class="space-y-4">
                    <div class="space-y-2">
                      <div class="skeleton h-4 w-24"></div>
                      <div class="skeleton h-12 w-full"></div>
                    </div>
                    <div class="space-y-2">
                      <div class="skeleton h-4 w-40"></div>
                      <div class="skeleton h-24 w-full"></div>
                    </div>
                  </div>
                </:skeleton>

                <div class="divider mx-6 my-0"></div>

                <%!-- Tab content: Title & Slug (translatable) --%>
                <div class="card-body pt-4 pb-4">
                  <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-3">
                    <.icon name="hero-information-circle" class="w-4 h-4 inline -mt-0.5" />
                    {gettext("Basic Information")}
                  </h3>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <.translatable_field
                      field_name="title"
                      form_prefix="phoenix_kit_entity_data"
                      changeset={@changeset}
                      schema_field={:title}
                      multilang_enabled={@multilang_enabled}
                      current_lang={@current_lang}
                      primary_language={@primary_language}
                      lang_data={lang_data}
                      label={gettext("Title")}
                      placeholder={gettext("Enter a title for this record")}
                      required
                      disabled={@readonly?}
                      class="w-full"
                    />

                    <.translatable_field
                      field_name="slug"
                      form_prefix="phoenix_kit_entity_data"
                      changeset={@changeset}
                      schema_field={:slug}
                      multilang_enabled={@multilang_enabled}
                      current_lang={@current_lang}
                      primary_language={@primary_language}
                      lang_data={lang_data}
                      label={gettext("Slug (URL-friendly identifier)")}
                      placeholder={gettext("auto-generated-slug")}
                      disabled={@readonly?}
                      class="w-full"
                      pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
                      title={gettext("Use lowercase letters, numbers, and hyphens only.")}
                      hint={gettext("Leave empty to auto-generate from title")}
                      secondary_hint={gettext("Leave empty to use the primary language slug")}
                    >
                      <:label_extra>
                        <button
                          type="button"
                          class="btn btn-ghost btn-xs ml-2"
                          phx-click="generate_slug"
                          title={gettext("Generate from title")}
                          disabled={@readonly?}
                        >
                          <.icon name="hero-arrow-path" class="w-3 h-3" /> {gettext("Generate")}
                        </button>
                      </:label_extra>
                    </.translatable_field>
                  </div>
                </div>

                <%= if @entity.fields_definition != nil and @entity.fields_definition != [] do %>
                  <div class="divider mx-6 my-0"></div>

                  <%!-- Tab content: Custom Fields (translatable) --%>
                  <div class="card-body pt-4">
                    <h3 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide mb-3">
                      <.icon name="hero-list-bullet" class="w-4 h-4 inline -mt-0.5" />
                      {gettext("Custom Fields")}
                    </h3>

                    <%!-- Dynamic form fields generated by FormBuilder --%>
                    {PhoenixKitEntities.FormBuilder.build_fields(@entity, f,
                      wrapper_class: "mb-6",
                      disabled: @readonly?,
                      lang_code: if(@multilang_enabled, do: @current_lang, else: nil)
                    )}
                  </div>
                <% end %>
              </.multilang_fields_wrapper>
            </div>

            <%!-- Record Settings (non-translatable, separate card) --%>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-lg mb-4">
                  <.icon name="hero-cog-6-tooth" class="w-5 h-5" />
                  {gettext("Record Settings")}
                </h2>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <%!-- Status --%>
                  <div>
                    <.label for="phoenix_kit_entity_data_status">{gettext("Status")}</.label>
                    <label class="select w-full">
                      <select
                        name="phoenix_kit_entity_data[status]"
                        disabled={@readonly?}
                      >
                        <option
                          value="draft"
                          selected={Ecto.Changeset.get_field(@changeset, :status) == "draft"}
                        >
                          {gettext("Draft")}
                        </option>
                        <option
                          value="published"
                          selected={Ecto.Changeset.get_field(@changeset, :status) == "published"}
                        >
                          {gettext("Published")}
                        </option>
                        <option
                          value="archived"
                          selected={Ecto.Changeset.get_field(@changeset, :status) == "archived"}
                        >
                          {gettext("Archived")}
                        </option>
                      </select>
                    </label>
                  </div>

                  <%!-- Entity Type (Read-only) --%>
                  <div>
                    <.label>{gettext("Entity Type")}</.label>
                    <div class="input input-bordered w-full bg-base-200 flex items-center">
                      <%= if @entity.icon do %>
                        <.icon name={@entity.icon} class="w-4 h-4 mr-2" />
                      <% end %>
                      {@entity.display_name}
                    </div>
                    <input
                      type="hidden"
                      name="phoenix_kit_entity_data[entity_uuid]"
                      value={@entity.uuid}
                    />
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <%!-- Non-multilang: separate cards (original layout) --%>
            <div class="card bg-base-100 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-2xl mb-4">
                  <.icon name="hero-information-circle" class="w-6 h-6" />
                  {gettext("Basic Information")}
                </h2>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <%!-- Title --%>
                  <div>
                    <.label for="phoenix_kit_entity_data_title">{gettext("Title")} *</.label>
                    <input
                      type="text"
                      name="phoenix_kit_entity_data[title]"
                      id="phoenix_kit_entity_data_title"
                      value={Ecto.Changeset.get_field(@changeset, :title) || ""}
                      placeholder={gettext("Enter a title for this record")}
                      class="input input-bordered w-full"
                      phx-debounce="300"
                      required
                      disabled={@readonly?}
                    />
                  </div>

                  <%!-- Slug with Generator --%>
                  <div>
                    <.label for="phoenix_kit_entity_data_slug">
                      {gettext("Slug (URL-friendly identifier)")}
                      <button
                        type="button"
                        class="btn btn-ghost btn-xs ml-2"
                        phx-click="generate_slug"
                        title={gettext("Generate from title")}
                        disabled={@readonly?}
                      >
                        <.icon name="hero-arrow-path" class="w-3 h-3" /> {gettext("Generate")}
                      </button>
                    </.label>
                    <input
                      type="text"
                      name="phoenix_kit_entity_data[slug]"
                      id="phoenix_kit_entity_data_slug"
                      value={Ecto.Changeset.get_field(@changeset, :slug) || ""}
                      placeholder={gettext("auto-generated-slug")}
                      class="input input-bordered w-full"
                      pattern="[a-z0-9]+(?:-[a-z0-9]+)*"
                      title={gettext("Use lowercase letters, numbers, and hyphens only.")}
                      phx-debounce="300"
                      disabled={@readonly?}
                    />
                    <.label class="label">
                      <span class="label-text-alt">
                        {gettext("Leave empty to auto-generate from title")}
                      </span>
                    </.label>
                  </div>

                  <%!-- Status --%>
                  <div>
                    <.label for="phoenix_kit_entity_data_status">{gettext("Status")}</.label>
                    <label class="select w-full">
                      <select
                        name="phoenix_kit_entity_data[status]"
                        disabled={@readonly?}
                      >
                        <option
                          value="draft"
                          selected={Ecto.Changeset.get_field(@changeset, :status) == "draft"}
                        >
                          {gettext("Draft")}
                        </option>
                        <option
                          value="published"
                          selected={Ecto.Changeset.get_field(@changeset, :status) == "published"}
                        >
                          {gettext("Published")}
                        </option>
                        <option
                          value="archived"
                          selected={Ecto.Changeset.get_field(@changeset, :status) == "archived"}
                        >
                          {gettext("Archived")}
                        </option>
                      </select>
                    </label>
                  </div>

                  <%!-- Entity Type (Read-only) --%>
                  <div>
                    <.label>{gettext("Entity Type")}</.label>
                    <div class="input input-bordered w-full bg-base-200 flex items-center">
                      <%= if @entity.icon do %>
                        <.icon name={@entity.icon} class="w-4 h-4 mr-2" />
                      <% end %>
                      {@entity.display_name}
                    </div>
                    <input
                      type="hidden"
                      name="phoenix_kit_entity_data[entity_uuid]"
                      value={@entity.uuid}
                    />
                  </div>
                </div>
              </div>
            </div>

            <%= if @entity.fields_definition != nil and @entity.fields_definition != [] do %>
              <div class="card bg-base-100 shadow-xl">
                <div class="card-body">
                  <h2 class="card-title text-2xl mb-4">
                    <.icon name="hero-list-bullet" class="w-6 h-6" /> {gettext("Custom Fields")}
                  </h2>

                  <%!-- Dynamic form fields generated by FormBuilder --%>
                  {PhoenixKitEntities.FormBuilder.build_fields(@entity, f,
                    wrapper_class: "mb-6",
                    disabled: @readonly?,
                    lang_code: nil
                  )}
                </div>
              </div>
            <% end %>
          <% end %>

          <%!-- Form Actions --%>
          <div class="flex justify-between items-center">
            <div class="flex gap-2">
              <.link
                navigate={PhoenixKit.Utils.Routes.path("/admin/entities/#{@entity.name}/data")}
                class="btn btn-outline"
              >
                {gettext("Cancel")}
              </.link>

              <button type="button" phx-click="reset" class="btn btn-warning" disabled={@readonly?}>
                <.icon name="hero-arrow-path" class="w-4 h-4" />
                {gettext("Reset Changes")}
              </button>
            </div>

            <button
              type="submit"
              class="btn btn-primary"
              disabled={@readonly?}
              phx-disable-with={gettext("Saving…")}
            >
              <.icon name="hero-check" class="w-4 h-4 mr-2" />
              <%= if @data_record.uuid do %>
                {gettext("Update %{entity}", entity: @entity.display_name)}
              <% else %>
                {gettext("Create %{entity}", entity: @entity.display_name)}
              <% end %>
            </button>
          </div>
        </.form>
      </div>
    """
  end
end
