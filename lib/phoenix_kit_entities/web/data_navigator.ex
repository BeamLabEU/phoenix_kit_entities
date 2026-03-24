defmodule PhoenixKitEntities.Web.DataNavigator do
  @moduledoc """
  LiveView for browsing and managing entity data records.
  Provides table view with pagination, search, filtering, and bulk operations.
  """

  use PhoenixKitWeb, :live_view
  on_mount(PhoenixKitEntities.Web.Hooks)

  alias PhoenixKit.Settings
  alias PhoenixKit.Users.Auth.Scope
  alias PhoenixKit.Utils.Multilang
  alias PhoenixKit.Utils.Routes
  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData
  alias PhoenixKitEntities.Events

  def mount(_params, _session, socket) do
    project_title = Settings.get_project_title()
    entities = Entities.list_entities()

    # Subscribe to entity definition events so we know about creates/updates/deletes
    if connected?(socket) do
      Events.subscribe_to_entities()
      Events.subscribe_to_all_data()
    end

    # Set defaults only — entity resolution and data loading deferred to handle_params
    socket =
      socket
      |> assign(:page_title, gettext("Data Navigator"))
      |> assign(:project_title, project_title)
      |> assign(:entities, entities)
      |> assign(:total_records, 0)
      |> assign(:published_records, 0)
      |> assign(:draft_records, 0)
      |> assign(:archived_records, 0)
      |> assign(:selected_entity, nil)
      |> assign(:selected_entity_uuid, nil)
      |> assign(:selected_status, "all")
      |> assign(:selected_uuids, MapSet.new())
      |> assign(:search_term, "")
      |> assign(:view_mode, "table")
      |> assign(:entity_data_records, [])

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    # Resolve entity from slug in params
    {entity, entity_uuid} = resolve_entity_from_params(params, socket)

    # Update stats if entity changed
    socket = maybe_update_entity_stats(socket, entity_uuid)

    # Set page title based on entity
    page_title =
      if entity, do: entity.display_name, else: gettext("Data Navigator")

    # Extract filter params with defaults
    status = params["status"] || "all"
    search_term = params["search"] || ""
    view_mode = params["view"] || "table"

    socket =
      socket
      |> assign(:page_title, page_title)
      |> assign(:selected_entity, entity)
      |> assign(:selected_entity_uuid, entity_uuid)
      |> assign(:selected_status, status)
      |> assign(:search_term, search_term)
      |> assign(:view_mode, view_mode)
      |> apply_filters()

    {:noreply, socket}
  end

  # Resolve entity and entity_uuid from URL params
  defp resolve_entity_from_params(params, socket) do
    case params["entity_slug"] || params["entity_id"] do
      nil ->
        {socket.assigns.selected_entity, socket.assigns.selected_entity_uuid}

      "" ->
        {nil, nil}

      slug when is_binary(slug) ->
        resolve_entity_by_slug(slug)
    end
  end

  # Look up entity by slug/name
  defp resolve_entity_by_slug(slug) do
    case Entities.get_entity_by_name(slug) do
      nil -> {nil, nil}
      entity -> {entity, entity.uuid}
    end
  end

  # Update entity stats if entity changed
  defp maybe_update_entity_stats(socket, new_entity_uuid) do
    if new_entity_uuid != socket.assigns.selected_entity_uuid do
      update_entity_stats(socket, new_entity_uuid)
    else
      socket
    end
  end

  # Update socket with fresh entity statistics
  defp update_entity_stats(socket, entity_uuid) do
    stats = EntityData.get_data_stats(entity_uuid)

    socket
    |> assign(:total_records, stats.total_records)
    |> assign(:published_records, stats.published_records)
    |> assign(:draft_records, stats.draft_records)
    |> assign(:archived_records, stats.archived_records)
  end

  def handle_event("toggle_view_mode", %{"mode" => mode}, socket) do
    params =
      build_url_params(
        socket.assigns.selected_entity_uuid,
        socket.assigns.selected_status,
        socket.assigns.search_term,
        mode
      )

    path = build_base_path(socket.assigns.selected_entity_uuid)
    full_path = if params != "", do: "#{path}?#{params}", else: path

    socket =
      socket
      |> assign(:view_mode, mode)
      |> assign(:selected_uuids, MapSet.new())
      |> push_patch(to: Routes.path(full_path, locale: socket.assigns.current_locale_base))

    {:noreply, socket}
  end

  def handle_event("filter_by_entity", %{"entity_uuid" => ""}, socket) do
    # No entity selected - redirect to entities list since global data view no longer exists
    socket =
      socket
      |> put_flash(:info, gettext("Please select an entity to view its data"))
      |> redirect(to: Routes.path("/admin/entities", locale: socket.assigns.current_locale_base))

    {:noreply, socket}
  end

  def handle_event("filter_by_entity", %{"entity_uuid" => entity_uuid}, socket) do
    params =
      build_url_params(
        entity_uuid,
        socket.assigns.selected_status,
        socket.assigns.search_term,
        socket.assigns.view_mode
      )

    path = build_base_path(entity_uuid)
    full_path = if params != "", do: "#{path}?#{params}", else: path

    socket =
      socket
      |> assign(:selected_uuids, MapSet.new())
      |> push_patch(to: Routes.path(full_path, locale: socket.assigns.current_locale_base))

    {:noreply, socket}
  end

  def handle_event("filter_by_status", %{"status" => status}, socket) do
    params =
      build_url_params(
        socket.assigns.selected_entity_uuid,
        status,
        socket.assigns.search_term,
        socket.assigns.view_mode
      )

    path = build_base_path(socket.assigns.selected_entity_uuid)
    full_path = if params != "", do: "#{path}?#{params}", else: path

    socket =
      socket
      |> assign(:selected_uuids, MapSet.new())
      |> push_patch(to: Routes.path(full_path, locale: socket.assigns.current_locale_base))

    {:noreply, socket}
  end

  def handle_event("search", %{"search" => %{"term" => term}}, socket) do
    params =
      build_url_params(
        socket.assigns.selected_entity_uuid,
        socket.assigns.selected_status,
        term,
        socket.assigns.view_mode
      )

    path = build_base_path(socket.assigns.selected_entity_uuid)
    full_path = if params != "", do: "#{path}?#{params}", else: path

    socket =
      socket
      |> assign(:selected_uuids, MapSet.new())
      |> push_patch(to: Routes.path(full_path, locale: socket.assigns.current_locale_base))

    {:noreply, socket}
  end

  def handle_event("clear_filters", _params, socket) do
    params =
      build_url_params(
        socket.assigns.selected_entity_uuid,
        "all",
        "",
        socket.assigns.view_mode
      )

    path = build_base_path(socket.assigns.selected_entity_uuid)
    full_path = if params != "", do: "#{path}?#{params}", else: path

    socket =
      socket
      |> assign(:selected_uuids, MapSet.new())
      |> push_patch(to: Routes.path(full_path, locale: socket.assigns.current_locale_base))

    {:noreply, socket}
  end

  def handle_event("archive_data", %{"uuid" => uuid}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      data_record = EntityData.get!(uuid)

      case EntityData.update_data(data_record, %{status: "archived"}) do
        {:ok, _data} ->
          socket =
            socket
            |> apply_filters()
            |> put_flash(:info, gettext("Data record archived successfully"))

          {:noreply, socket}

        {:error, _changeset} ->
          socket = put_flash(socket, :error, gettext("Failed to archive data record"))
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("restore_data", %{"uuid" => uuid}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      data_record = EntityData.get!(uuid)

      case EntityData.update_data(data_record, %{status: "published"}) do
        {:ok, _data} ->
          socket =
            socket
            |> apply_filters()
            |> put_flash(:info, gettext("Data record restored successfully"))

          {:noreply, socket}

        {:error, _changeset} ->
          socket = put_flash(socket, :error, gettext("Failed to restore data record"))
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("toggle_status", %{"uuid" => uuid}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      data_record = EntityData.get!(uuid)

      new_status =
        case data_record.status do
          "draft" -> "published"
          "published" -> "archived"
          "archived" -> "draft"
        end

      case EntityData.update_data(data_record, %{status: new_status}) do
        {:ok, _updated_data} ->
          socket =
            socket
            |> refresh_data_stats()
            |> apply_filters()
            |> put_flash(
              :info,
              gettext("Status updated to %{status}", status: status_label(new_status))
            )

          {:noreply, socket}

        {:error, _changeset} ->
          socket = put_flash(socket, :error, gettext("Failed to update status"))
          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("toggle_select", %{"uuid" => uuid}, socket) do
    selected = socket.assigns.selected_uuids

    selected =
      if MapSet.member?(selected, uuid),
        do: MapSet.delete(selected, uuid),
        else: MapSet.put(selected, uuid)

    {:noreply, assign(socket, :selected_uuids, selected)}
  end

  def handle_event("select_all", _params, socket) do
    all_uuids = socket.assigns.entity_data_records |> Enum.map(& &1.uuid) |> MapSet.new()
    {:noreply, assign(socket, :selected_uuids, all_uuids)}
  end

  def handle_event("deselect_all", _params, socket) do
    {:noreply, assign(socket, :selected_uuids, MapSet.new())}
  end

  def handle_event("bulk_action", %{"action" => "archive"}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      uuids = socket.assigns.selected_uuids

      if MapSet.size(uuids) == 0 do
        {:noreply, put_flash(socket, :error, gettext("No records selected"))}
      else
        {count, _} = EntityData.bulk_update_status(MapSet.to_list(uuids), "archived")

        {:noreply,
         socket
         |> assign(:selected_uuids, MapSet.new())
         |> refresh_data_stats()
         |> apply_filters()
         |> put_flash(:info, gettext("%{count} records archived", count: count))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("bulk_action", %{"action" => "restore"}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      uuids = socket.assigns.selected_uuids

      if MapSet.size(uuids) == 0 do
        {:noreply, put_flash(socket, :error, gettext("No records selected"))}
      else
        {count, _} = EntityData.bulk_update_status(MapSet.to_list(uuids), "published")

        {:noreply,
         socket
         |> assign(:selected_uuids, MapSet.new())
         |> refresh_data_stats()
         |> apply_filters()
         |> put_flash(:info, gettext("%{count} records restored", count: count))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("bulk_action", %{"action" => "delete"}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      uuids = socket.assigns.selected_uuids

      if MapSet.size(uuids) == 0 do
        {:noreply, put_flash(socket, :error, gettext("No records selected"))}
      else
        {count, _} = EntityData.bulk_delete(MapSet.to_list(uuids))

        {:noreply,
         socket
         |> assign(:selected_uuids, MapSet.new())
         |> refresh_data_stats()
         |> apply_filters()
         |> put_flash(:info, gettext("%{count} records deleted", count: count))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  def handle_event("bulk_action", %{"action" => "change_status", "status" => status}, socket) do
    if Scope.admin?(socket.assigns.phoenix_kit_current_scope) do
      uuids = socket.assigns.selected_uuids

      if MapSet.size(uuids) == 0 do
        {:noreply, put_flash(socket, :error, gettext("No records selected"))}
      else
        {count, _} = EntityData.bulk_update_status(MapSet.to_list(uuids), status)

        {:noreply,
         socket
         |> assign(:selected_uuids, MapSet.new())
         |> refresh_data_stats()
         |> apply_filters()
         |> put_flash(:info, gettext("%{count} records updated", count: count))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Not authorized"))}
    end
  end

  ## Live updates

  def handle_info({:entity_created, _entity_uuid}, socket) do
    {:noreply, refresh_entities_and_data(socket)}
  end

  def handle_info({:entity_updated, entity_uuid}, socket) do
    # If the currently viewed entity was updated, check if it was archived
    if socket.assigns.selected_entity_uuid && entity_uuid == socket.assigns.selected_entity_uuid do
      entity = Entities.get_entity!(entity_uuid)

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
        # Update the selected entity and page title with fresh data
        socket =
          socket
          |> assign(:selected_entity, entity)
          |> assign(:page_title, entity.display_name)
          |> refresh_entities_and_data()

        {:noreply, socket}
      end
    else
      {:noreply, refresh_entities_and_data(socket)}
    end
  end

  def handle_info({:entity_deleted, entity_uuid}, socket) do
    # If the currently viewed entity was deleted, redirect to entities list
    if socket.assigns.selected_entity_uuid && entity_uuid == socket.assigns.selected_entity_uuid do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Entity was deleted in another session."))
       |> redirect(to: Routes.path("/admin/entities", locale: socket.assigns.current_locale_base))}
    else
      {:noreply, refresh_entities_and_data(socket)}
    end
  end

  def handle_info({event, _entity_uuid, _data_uuid}, socket)
      when event in [:data_created, :data_updated, :data_deleted] do
    socket =
      socket
      |> refresh_data_stats()
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_info({:data_reordered, _entity_uuid}, socket) do
    {:noreply, apply_filters(socket)}
  end

  # Helper Functions

  defp build_base_path(nil), do: "/admin/entities"

  defp build_base_path(entity_uuid) when is_binary(entity_uuid) do
    case Entities.get_entity(entity_uuid) do
      nil -> "/admin/entities"
      entity -> "/admin/entities/#{entity.name}/data"
    end
  end

  defp build_url_params(_entity_uuid, status, search_term, view_mode) do
    params = []

    # Don't include entity_uuid in query params since it's in the path

    params =
      if status && status != "all" do
        [{"status", status} | params]
      else
        params
      end

    params =
      if search_term && String.trim(search_term) != "" do
        [{"search", search_term} | params]
      else
        params
      end

    params =
      if view_mode && view_mode != "table" do
        [{"view", view_mode} | params]
      else
        params
      end

    URI.encode_query(params)
  end

  defp apply_filters(socket) do
    entity = socket.assigns[:selected_entity]
    entity_uuid = socket.assigns[:selected_entity_uuid]
    status = socket.assigns[:selected_status] || "all"
    search_term = socket.assigns[:search_term] || ""

    # Pass sort_mode from the already-loaded entity to avoid redundant DB lookups
    sort_opts =
      if entity, do: [sort_mode: Entities.get_sort_mode(entity)], else: []

    entity_data_records =
      fetch_records(entity_uuid, status, sort_opts)
      |> filter_by_search(search_term)

    assign(socket, :entity_data_records, entity_data_records)
  end

  # When an entity is selected, use sort-mode-aware queries
  defp fetch_records(nil, "all", _opts), do: EntityData.list_all_data()
  defp fetch_records(nil, status, _opts), do: EntityData.list_data_by_status(status)

  defp fetch_records(entity_uuid, "all", opts),
    do: EntityData.list_by_entity(entity_uuid, opts)

  defp fetch_records(entity_uuid, status, opts),
    do: EntityData.list_by_entity_and_status(entity_uuid, status, opts)

  defp filter_by_search(records, ""), do: records

  defp filter_by_search(records, search_term) do
    search_term_lower = String.downcase(String.trim(search_term))

    Enum.filter(records, fn record ->
      title_match = String.contains?(String.downcase(record.title || ""), search_term_lower)
      slug_match = String.contains?(String.downcase(record.slug || ""), search_term_lower)

      title_match || slug_match
    end)
  end

  defp refresh_data_stats(socket) do
    stats = EntityData.get_data_stats(socket.assigns.selected_entity_uuid)

    socket
    |> assign(:total_records, stats.total_records)
    |> assign(:published_records, stats.published_records)
    |> assign(:draft_records, stats.draft_records)
    |> assign(:archived_records, stats.archived_records)
  end

  defp refresh_entities_and_data(socket) do
    socket
    |> assign(:entities, Entities.list_entities())
    |> refresh_data_stats()
    |> apply_filters()
  end

  def status_badge_class(status) do
    case status do
      "published" -> "badge-success"
      "draft" -> "badge-warning"
      "archived" -> "badge-neutral"
      _ -> "badge-outline"
    end
  end

  def status_label(status) do
    case status do
      "published" -> gettext("Published")
      "draft" -> gettext("Draft")
      "archived" -> gettext("Archived")
      _ -> gettext("Unknown")
    end
  end

  def status_icon(status) do
    case status do
      "published" -> "hero-check-circle"
      "draft" -> "hero-pencil"
      "archived" -> "hero-archive-box"
      _ -> "hero-question-mark-circle"
    end
  end

  def get_entity_name(entities, entity_uuid) do
    case Enum.find(entities, &(&1.uuid == entity_uuid)) do
      nil -> gettext("Unknown")
      entity -> entity.display_name
    end
  end

  def get_entity_slug(entities, entity_uuid) do
    case Enum.find(entities, &(&1.uuid == entity_uuid)) do
      nil -> ""
      entity -> entity.name
    end
  end

  def truncate_text(text, length \\ 100)

  def truncate_text(text, length) when is_binary(text) do
    if String.length(text) > length do
      String.slice(text, 0, length) <> "..."
    else
      text
    end
  end

  def truncate_text(_, _), do: ""

  def format_data_preview(data) when is_map(data) do
    # For multilang data, show primary language fields
    display_data =
      if Multilang.multilang_data?(data) do
        Multilang.flatten_to_primary(data)
      else
        data
      end

    display_data
    |> Enum.take(3)
    |> Enum.map_join(" • ", fn {key, value} ->
      "#{key}: #{truncate_text(to_string(value), 30)}"
    end)
  end

  def format_data_preview(_), do: ""

  @impl true
  def render(assigns) do
    ~H"""
      <div class="container flex flex-col mx-auto px-4 py-6">
        <%!-- Header Section --%>
        <.admin_page_header back={PhoenixKit.Utils.Routes.path("/admin/entities")}>
          <%= if @selected_entity do %>
            <h1 class="text-xl sm:text-2xl lg:text-3xl font-bold text-base-content">
              {@selected_entity.display_name_plural || @selected_entity.display_name}
            </h1>
            <p class="text-sm text-base-content/60 mt-0.5">
              {gettext("Browse and manage your %{entity}",
                entity:
                  String.downcase(
                    @selected_entity.display_name_plural || @selected_entity.display_name
                  )
              )}
            </p>
          <% else %>
            <h1 class="text-xl sm:text-2xl lg:text-3xl font-bold text-base-content">
              {gettext("Data Navigator")}
            </h1>
            <p class="text-sm text-base-content/60 mt-0.5">
              {gettext("Browse and manage all entity data records across your system")}
            </p>
          <% end %>
        </.admin_page_header>

        <%!-- Stats Cards --%>
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div class="bg-primary text-primary-content rounded-2xl p-6 shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105">
            <div class="flex items-center justify-between mb-4">
              <div class="p-2 bg-base-100/20 rounded-lg">
                <.icon name="hero-circle-stack" class="w-6 h-6" />
              </div>
            </div>
            <div class="text-3xl font-bold mb-2">{@total_records}</div>
            <div class="opacity-90 font-medium">{gettext("Total Records")}</div>
            <div class="opacity-70 text-xs mt-1">{gettext("All data records")}</div>
          </div>

          <div class="bg-success text-success-content rounded-2xl p-6 shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105">
            <div class="flex items-center justify-between mb-4">
              <div class="p-2 bg-base-100/20 rounded-lg">
                <.icon name="hero-bolt" class="w-6 h-6" />
              </div>
            </div>
            <div class="text-3xl font-bold mb-2">{@published_records}</div>
            <div class="opacity-90 font-medium">{gettext("Published")}</div>
            <div class="opacity-70 text-xs mt-1">{gettext("Live content")}</div>
          </div>

          <div class="bg-warning text-warning-content rounded-2xl p-6 shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105">
            <div class="flex items-center justify-between mb-4">
              <div class="p-2 bg-base-100/20 rounded-lg">
                <.icon name="hero-pencil" class="w-6 h-6" />
              </div>
            </div>
            <div class="text-3xl font-bold mb-2">{@draft_records}</div>
            <div class="opacity-90 font-medium">{gettext("Drafts")}</div>
            <div class="opacity-70 text-xs mt-1">{gettext("Work in progress")}</div>
          </div>

          <div class="bg-neutral text-neutral-content rounded-2xl p-6 shadow-xl hover:shadow-2xl transition-all duration-300 transform hover:scale-105">
            <div class="flex items-center justify-between mb-4">
              <div class="p-2 bg-base-100/20 rounded-lg">
                <.icon name="hero-archive-box" class="w-6 h-6" />
              </div>
            </div>
            <div class="text-3xl font-bold mb-2">{@archived_records}</div>
            <div class="opacity-90 font-medium">{gettext("Archived")}</div>
            <div class="opacity-70 text-xs mt-1">{gettext("Stored content")}</div>
          </div>
        </div>

        <%!-- Action Bar --%>
        <div class="flex flex-col sm:flex-row justify-end items-start sm:items-center mb-6 gap-4">
          <div class="flex gap-2 items-center">
            <%!-- View Mode Toggle --%>
            <div class="join">
              <button
                type="button"
                phx-click="toggle_view_mode"
                phx-value-mode="card"
                class={["btn join-item", @view_mode == "card" && "btn-active"]}
                title={gettext("Card view")}
              >
                <.icon name="hero-squares-2x2" class="w-4 h-4" />
              </button>
              <button
                type="button"
                phx-click="toggle_view_mode"
                phx-value-mode="table"
                class={["btn join-item", @view_mode == "table" && "btn-active"]}
                title={gettext("Table view")}
              >
                <.icon name="hero-bars-3-bottom-left" class="w-4 h-4" />
              </button>
            </div>

            <%= if @selected_entity do %>
              <.link
                navigate={
                  PhoenixKit.Utils.Routes.path("/admin/entities/#{@selected_entity.uuid}/edit")
                }
                class="btn btn-outline"
              >
                <.icon name="hero-cog-6-tooth" class="w-4 h-4 mr-2" /> {gettext("Edit Entity")}
              </.link>
            <% end %>
            <%= if not Enum.empty?(@entities) do %>
              <%= if @selected_entity do %>
                <%!-- Direct add button when viewing specific entity --%>
                <.link
                  navigate={
                    PhoenixKit.Utils.Routes.path("/admin/entities/#{@selected_entity.name}/data/new")
                  }
                  class="btn btn-primary"
                >
                  <.icon name="hero-plus" class="w-4 h-4 mr-2" /> {gettext("Add")}
                </.link>
              <% else %>
                <%!-- Dropdown to select entity when viewing all data --%>
                <div class="dropdown dropdown-end">
                  <label tabindex="0" class="btn btn-primary">
                    <.icon name="hero-plus" class="w-4 h-4 mr-2" /> {gettext("Add")}
                    <.icon name="hero-chevron-down" class="w-4 h-4 ml-2" />
                  </label>
                  <ul
                    tabindex="0"
                    class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-64 mt-2"
                  >
                    <li class="menu-title">
                      <span>{gettext("Select Entity Type")}</span>
                    </li>
                    <%= for entity <- @entities do %>
                      <%= if entity.status == "published" do %>
                        <li>
                          <.link
                            navigate={
                              PhoenixKit.Utils.Routes.path("/admin/entities/#{entity.name}/data/new")
                            }
                            class="flex items-center justify-between"
                          >
                            <span>{entity.display_name}</span>
                            <span class="badge badge-sm badge-ghost">{entity.name}</span>
                          </.link>
                        </li>
                      <% end %>
                    <% end %>
                    <%= if Enum.all?(@entities, & &1.status != "published") do %>
                      <li class="disabled">
                        <span class="text-sm text-base-content/50">
                          {gettext("No published entities available. Publish an entity first.")}
                        </span>
                      </li>
                    <% end %>
                  </ul>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Filters Section --%>
        <div class="card bg-base-100 shadow-xl mb-6">
          <div class="card-body">
            <h2 class="card-title text-xl mb-4">
              <.icon name="hero-funnel" class="w-5 h-5" /> {gettext("Filters & Search")}
            </h2>

            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <%!-- Status Filter --%>
              <div>
                <label class="label">
                  <span class="label-text">{gettext("Filter by Status")}</span>
                </label>
                <.form for={%{}} phx-change="filter_by_status">
                  <select class="select select-bordered w-full" name="status">
                    <option value="all" selected={@selected_status == "all"}>
                      {gettext("All Statuses")}
                    </option>
                    <option value="published" selected={@selected_status == "published"}>
                      {gettext("Published")}
                    </option>
                    <option value="draft" selected={@selected_status == "draft"}>
                      {gettext("Draft")}
                    </option>
                    <option value="archived" selected={@selected_status == "archived"}>
                      {gettext("Archived")}
                    </option>
                  </select>
                </.form>
              </div>

              <%!-- Search --%>
              <div>
                <label class="label">
                  <span class="label-text">{gettext("Search Records")}</span>
                </label>
                <.form for={%{}} phx-change="search" phx-submit="search" class="join w-full">
                  <input
                    type="text"
                    name="search[term]"
                    value={@search_term}
                    placeholder={gettext("Search by title or slug...")}
                    class="input input-bordered join-item flex-1"
                  />
                  <button type="submit" class="btn btn-primary join-item">
                    <.icon name="hero-magnifying-glass" class="w-4 h-4" />
                  </button>
                </.form>
              </div>
            </div>

            <%!-- Clear Filters --%>
            <%= if @selected_status != "all" || @search_term != "" do %>
              <div class="flex justify-end mt-4">
                <button phx-click="clear_filters" class="btn btn-outline btn-sm">
                  <.icon name="hero-x-mark" class="w-4 h-4 mr-2" /> {gettext("Clear All Filters")}
                </button>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Bulk Actions Bar --%>
        <%= if MapSet.size(@selected_uuids) > 0 do %>
          <div class="card bg-base-200 shadow-xl mb-6">
            <div class="card-body p-4">
              <div class="flex flex-wrap gap-3 items-center">
                <span class="text-sm font-semibold">
                  {MapSet.size(@selected_uuids)} {gettext("selected")}
                </span>
                <div class="divider divider-horizontal mx-0"></div>
                <%!-- Quick Actions --%>
                <button
                  phx-click="bulk_action"
                  phx-value-action="archive"
                  class="btn btn-warning btn-sm"
                >
                  <.icon name="hero-archive-box" class="w-4 h-4" /> {gettext("Archive")}
                </button>
                <button
                  phx-click="bulk_action"
                  phx-value-action="restore"
                  class="btn btn-success btn-sm"
                >
                  <.icon name="hero-arrow-path" class="w-4 h-4" /> {gettext("Restore")}
                </button>
                <button
                  phx-click="bulk_action"
                  phx-value-action="delete"
                  class="btn btn-error btn-sm"
                  data-confirm={
                    gettext("Are you sure you want to delete %{count} records?",
                      count: MapSet.size(@selected_uuids)
                    )
                  }
                >
                  <.icon name="hero-trash" class="w-4 h-4" /> {gettext("Delete")}
                </button>

                <div class="divider divider-horizontal mx-0"></div>

                <%!-- Change Status Dropdown --%>
                <div class="dropdown">
                  <label tabindex="0" class="btn btn-ghost btn-sm">
                    <.icon name="hero-arrow-path-rounded-square" class="w-4 h-4" />
                    {gettext("Change Status")}
                    <.icon name="hero-chevron-down" class="w-4 h-4" />
                  </label>
                  <ul
                    tabindex="0"
                    class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-52"
                  >
                    <li>
                      <a
                        phx-click="bulk_action"
                        phx-value-action="change_status"
                        phx-value-status="published"
                      >
                        {gettext("Published")}
                      </a>
                    </li>
                    <li>
                      <a
                        phx-click="bulk_action"
                        phx-value-action="change_status"
                        phx-value-status="draft"
                      >
                        {gettext("Draft")}
                      </a>
                    </li>
                    <li>
                      <a
                        phx-click="bulk_action"
                        phx-value-action="change_status"
                        phx-value-status="archived"
                      >
                        {gettext("Archived")}
                      </a>
                    </li>
                  </ul>
                </div>
                <div class="flex-1"></div>
                <button phx-click="deselect_all" class="btn btn-ghost btn-sm">
                  <.icon name="hero-x-mark" class="w-4 h-4" /> {gettext("Clear")}
                </button>
              </div>
            </div>
          </div>
        <% end %>

        <%!-- Results Section --%>
        <%= if Enum.empty?(@entity_data_records) do %>
          <%!-- Empty State --%>
          <div class="card bg-base-100 shadow-xl border-2 border-dashed border-base-300">
            <div class="card-body text-center py-12">
              <div class="text-6xl mb-4 opacity-50">📄</div>
              <%= if Enum.empty?(@entities) do %>
                <%!-- No entities exist --%>
                <h3 class="text-2xl font-semibold text-base-content/60 mb-4">
                  {gettext("No Entities Created Yet")}
                </h3>
                <p class="text-base-content/50 mb-6 max-w-md mx-auto">
                  {gettext("Create your first entity to start managing data records.")}
                </p>
                <.link
                  navigate={PhoenixKit.Utils.Routes.path("/admin/entities")}
                  class="btn btn-primary btn-lg"
                >
                  <.icon name="hero-plus" class="w-5 h-5 mr-2" /> {gettext("Create Your First Entity")}
                </.link>
              <% else %>
                <%= if @total_records == 0 do %>
                  <%!-- Entities exist but no data records at all --%>
                  <h3 class="text-2xl font-semibold text-base-content/60 mb-4">
                    {gettext("No Data Records Yet")}
                  </h3>
                  <p class="text-base-content/50 mb-6 max-w-md mx-auto">
                    {gettext("Get started by adding your first data record.")}
                  </p>
                  <%= if @selected_entity do %>
                    <%!-- Direct add button when viewing specific entity --%>
                    <.link
                      navigate={
                        PhoenixKit.Utils.Routes.path(
                          "/admin/entities/#{@selected_entity.name}/data/new"
                        )
                      }
                      class="btn btn-primary btn-lg"
                    >
                      <.icon name="hero-plus" class="w-5 h-5 mr-2" /> {gettext("Add")}
                    </.link>
                  <% else %>
                    <%!-- Dropdown to select entity when viewing all data --%>
                    <div class="dropdown dropdown-top dropdown-center">
                      <label tabindex="0" class="btn btn-primary btn-lg">
                        <.icon name="hero-plus" class="w-5 h-5 mr-2" /> {gettext("Add")}
                        <.icon name="hero-chevron-down" class="w-5 h-5 ml-2" />
                      </label>
                      <ul
                        tabindex="0"
                        class="dropdown-content z-[1] menu p-2 shadow-lg bg-base-100 rounded-box w-72 mb-2 left-1/2 -translate-x-1/2"
                      >
                        <li class="menu-title">
                          <span>{gettext("Select Entity Type")}</span>
                        </li>
                        <%= for entity <- @entities do %>
                          <%= if entity.status == "published" do %>
                            <li>
                              <.link
                                navigate={
                                  PhoenixKit.Utils.Routes.path(
                                    "/admin/entities/#{entity.name}/data/new"
                                  )
                                }
                                class="flex items-center justify-between"
                              >
                                <span>{entity.display_name}</span>
                                <span class="badge badge-sm badge-ghost">{entity.name}</span>
                              </.link>
                            </li>
                          <% end %>
                        <% end %>
                        <%= if Enum.all?(@entities, & &1.status != "published") do %>
                          <li class="disabled">
                            <span class="text-sm text-base-content/50 p-4">
                              {gettext(
                                "No published entities available. Publish an entity first to create data."
                              )}
                            </span>
                          </li>
                        <% end %>
                      </ul>
                    </div>
                  <% end %>
                <% else %>
                  <%= if @selected_entity_uuid || @selected_status != "all" || @search_term != "" do %>
                    <%!-- Data exists but filters exclude everything --%>
                    <h3 class="text-2xl font-semibold text-base-content/60 mb-4">
                      {gettext("No Data Records Found")}
                    </h3>
                    <p class="text-base-content/50 mb-6 max-w-md mx-auto">
                      {gettext(
                        "No data records match your current filters. Try adjusting your search criteria or clearing the filters."
                      )}
                    </p>
                    <button phx-click="clear_filters" class="btn btn-outline btn-lg">
                      <.icon name="hero-x-mark" class="w-5 h-5 mr-2" /> {gettext("Clear Filters")}
                    </button>
                  <% end %>
                <% end %>
              <% end %>
            </div>
          </div>
        <% else %>
          <%!-- Data Records View --%>
          <%= if @view_mode == "table" do %>
            <%!-- Table View --%>
            <.table_default variant="zebra" size="sm">
              <.table_default_header>
                <.table_default_row>
                  <.table_default_header_cell class="w-12">
                    <%= if length(@entity_data_records) > 0 do %>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        checked={
                          MapSet.size(@selected_uuids) == length(@entity_data_records) &&
                            length(@entity_data_records) > 0
                        }
                        phx-click={
                          if MapSet.size(@selected_uuids) == length(@entity_data_records),
                            do: "deselect_all",
                            else: "select_all"
                        }
                        title={gettext("Select all")}
                      />
                    <% end %>
                  </.table_default_header_cell>
                  <.table_default_header_cell>{gettext("Title")}</.table_default_header_cell>
                  <%= if !@selected_entity do %>
                    <.table_default_header_cell>{gettext("Entity")}</.table_default_header_cell>
                  <% end %>
                  <.table_default_header_cell>{gettext("Status")}</.table_default_header_cell>
                  <.table_default_header_cell>{gettext("Created")}</.table_default_header_cell>
                  <.table_default_header_cell>{gettext("Actions")}</.table_default_header_cell>
                </.table_default_row>
              </.table_default_header>
              <.table_default_body>
                <%= for data_record <- @entity_data_records do %>
                  <.table_default_row>
                    <.table_default_cell>
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select"
                        phx-value-uuid={data_record.uuid}
                        checked={MapSet.member?(@selected_uuids, data_record.uuid)}
                      />
                    </.table_default_cell>
                    <.table_default_cell>
                      <.link
                        navigate={
                          PhoenixKit.Utils.Routes.path(
                            "/admin/entities/#{get_entity_slug(@entities, data_record.entity_uuid)}/data/#{data_record.uuid}"
                          )
                        }
                        class="block hover:text-primary transition-colors cursor-pointer"
                      >
                        <div class="font-bold">{data_record.title}</div>
                        <%= if data_record.slug do %>
                          <div class="text-sm opacity-50">
                            <.icon name="hero-link" class="w-3 h-3 inline" />
                            {data_record.slug}
                          </div>
                        <% end %>
                      </.link>
                    </.table_default_cell>
                    <%= if !@selected_entity do %>
                      <.table_default_cell>
                        <span class="badge badge-outline badge-sm h-auto">
                          {get_entity_name(@entities, data_record.entity_uuid)}
                        </span>
                      </.table_default_cell>
                    <% end %>
                    <.table_default_cell>
                      <span class={"badge #{status_badge_class(data_record.status)} badge-sm"}>
                        <.icon name={status_icon(data_record.status)} class="w-3 h-3 mr-1" />
                        {status_label(data_record.status)}
                      </span>
                    </.table_default_cell>
                    <.table_default_cell>
                      <div class="text-sm">
                        {PhoenixKit.Utils.Date.format_date_with_user_format(data_record.date_created)}
                      </div>
                      <%= if data_record.creator do %>
                        <div class="text-xs opacity-50">
                          {data_record.creator.email}
                        </div>
                      <% end %>
                    </.table_default_cell>
                    <.table_default_cell>
                      <div class="flex gap-2">
                        <.link
                          navigate={
                            PhoenixKit.Utils.Routes.path(
                              "/admin/entities/#{get_entity_slug(@entities, data_record.entity_uuid)}/data/#{data_record.uuid}"
                            )
                          }
                          class="btn btn-outline btn-xs tooltip tooltip-bottom"
                          data-tip={gettext("View")}
                        >
                          <.icon name="hero-eye" class="w-4 h-4 hidden sm:inline" />
                          <span class="sm:hidden whitespace-nowrap">{gettext("View")}</span>
                        </.link>
                        <.link
                          navigate={
                            PhoenixKit.Utils.Routes.path(
                              "/admin/entities/#{get_entity_slug(@entities, data_record.entity_uuid)}/data/#{data_record.uuid}/edit"
                            )
                          }
                          class="btn btn-outline btn-xs tooltip tooltip-bottom"
                          data-tip={gettext("Edit")}
                        >
                          <.icon name="hero-pencil" class="w-4 h-4 hidden sm:inline" />
                          <span class="sm:hidden whitespace-nowrap">{gettext("Edit")}</span>
                        </.link>
                        <%= if data_record.status == "archived" do %>
                          <button
                            class="btn btn-outline btn-xs text-success tooltip tooltip-bottom"
                            phx-click="restore_data"
                            phx-value-uuid={data_record.uuid}
                            data-tip={gettext("Restore")}
                          >
                            <.icon name="hero-arrow-path" class="w-4 h-4 hidden sm:inline" />
                            <span class="sm:hidden whitespace-nowrap">{gettext("Restore")}</span>
                          </button>
                        <% else %>
                          <button
                            class="btn btn-outline btn-xs text-error tooltip tooltip-bottom"
                            phx-click="archive_data"
                            phx-value-uuid={data_record.uuid}
                            data-tip={gettext("Archive")}
                          >
                            <.icon name="hero-trash" class="w-4 h-4 hidden sm:inline" />
                            <span class="sm:hidden whitespace-nowrap">{gettext("Archive")}</span>
                          </button>
                        <% end %>
                      </div>
                    </.table_default_cell>
                  </.table_default_row>
                <% end %>
              </.table_default_body>
            </.table_default>
          <% else %>
            <%!-- Card View --%>
            <div class="grid gap-6">
              <%= for data_record <- @entity_data_records do %>
                <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
                  <div class="card-body">
                    <div class="flex items-start gap-3 mb-4">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-md mt-1"
                        phx-click="toggle_select"
                        phx-value-uuid={data_record.uuid}
                        checked={MapSet.member?(@selected_uuids, data_record.uuid)}
                      />
                      <div class="flex-1">
                        <div class="flex items-start justify-between mb-2">
                          <.link
                            navigate={
                              PhoenixKit.Utils.Routes.path(
                                "/admin/entities/#{get_entity_slug(@entities, data_record.entity_uuid)}/data/#{data_record.uuid}"
                              )
                            }
                            class="flex-1 hover:text-primary transition-colors cursor-pointer"
                          >
                            <%!-- Title and Entity Info --%>
                            <div class="flex items-center mb-2">
                              <h3 class="card-title text-lg mr-3">{data_record.title}</h3>
                              <%= if !@selected_entity do %>
                                <span class="badge badge-outline">
                                  {get_entity_name(@entities, data_record.entity_uuid)}
                                </span>
                              <% end %>
                            </div>

                            <%!-- Slug --%>
                            <%= if data_record.slug do %>
                              <p class="text-sm text-base-content/60 mb-2">
                                <.icon name="hero-link" class="w-4 h-4 inline mr-1" />
                                {data_record.slug}
                              </p>
                            <% end %>

                            <%!-- Data Preview --%>
                            <%= if data_record.data && map_size(data_record.data) > 0 do %>
                              <p class="text-sm text-base-content/70 mb-3">
                                {format_data_preview(data_record.data)}
                              </p>
                            <% end %>
                          </.link>

                          <%!-- Status Badge --%>
                          <div class="flex flex-col items-end">
                            <span class={"badge #{status_badge_class(data_record.status)} mb-2"}>
                              <.icon name={status_icon(data_record.status)} class="w-3 h-3 mr-1" />
                              {status_label(data_record.status)}
                            </span>

                            <%!-- Status Toggle Button --%>
                            <button
                              class="btn btn-ghost btn-xs"
                              phx-click="toggle_status"
                              phx-value-uuid={data_record.uuid}
                              title={gettext("Cycle status")}
                            >
                              <.icon name="hero-arrow-path" class="w-3 h-3" />
                            </button>
                          </div>
                        </div>

                        <%!-- Metadata Row --%>
                        <div class="flex flex-wrap items-center gap-4 text-xs text-base-content/50 mb-4">
                          <%= if data_record.creator do %>
                            <span>
                              <.icon name="hero-user" class="w-3 h-3 inline mr-1" />
                              {data_record.creator.email}
                            </span>
                          <% end %>
                          <span>
                            <.icon name="hero-calendar" class="w-3 h-3 inline mr-1" />
                            {gettext("Created")} {PhoenixKit.Utils.Date.format_date_with_user_format(
                              data_record.date_created
                            )}
                          </span>
                          <%= if data_record.date_updated != data_record.date_created do %>
                            <span>
                              <.icon name="hero-clock" class="w-3 h-3 inline mr-1" />
                              {gettext("Updated")} {PhoenixKit.Utils.Date.format_date_with_user_format(
                                data_record.date_updated
                              )}
                            </span>
                          <% end %>
                        </div>
                      </div>
                    </div>

                    <%!-- Actions --%>
                    <div class="card-actions justify-end">
                      <.link
                        navigate={
                          PhoenixKit.Utils.Routes.path(
                            "/admin/entities/#{get_entity_slug(@entities, data_record.entity_uuid)}/data/#{data_record.uuid}"
                          )
                        }
                        class="btn btn-outline btn-sm"
                      >
                        <.icon name="hero-eye" class="w-4 h-4 mr-1" /> {gettext("View")}
                      </.link>
                      <.link
                        navigate={
                          PhoenixKit.Utils.Routes.path(
                            "/admin/entities/#{get_entity_slug(@entities, data_record.entity_uuid)}/data/#{data_record.uuid}/edit"
                          )
                        }
                        class="btn btn-primary btn-sm"
                      >
                        <.icon name="hero-pencil" class="w-4 h-4 mr-1" /> {gettext("Edit")}
                      </.link>

                      <%!-- Archive/Restore Button --%>
                      <%= if data_record.status == "archived" do %>
                        <button
                          class="btn btn-success btn-sm"
                          phx-click="restore_data"
                          phx-value-uuid={data_record.uuid}
                          title={gettext("Restore data record")}
                        >
                          <.icon name="hero-arrow-path" class="w-4 h-4" />
                        </button>
                      <% else %>
                        <button
                          class="btn btn-error btn-sm"
                          phx-click="archive_data"
                          phx-value-uuid={data_record.uuid}
                          title={gettext("Archive data record")}
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                        </button>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    """
  end
end
