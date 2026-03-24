defmodule PhoenixKitEntities.Web.Entities do
  @moduledoc """
  LiveView for listing and managing all entities.
  Provides interface for viewing, publishing, and deleting entity schemas.
  """

  use PhoenixKitWeb, :live_view
  on_mount(PhoenixKitEntities.Web.Hooks)

  alias PhoenixKit.Settings
  alias PhoenixKitEntities, as: Entities

  def mount(params, _session, socket) do
    # Set locale for LiveView process
    locale =
      params["locale"] || socket.assigns[:current_locale]

    project_title = Settings.get_project_title()

    socket =
      socket
      |> assign(:current_locale, locale)
      |> assign(:page_title, gettext("Entities"))
      |> assign(:project_title, project_title)
      |> assign(:view_mode, "table")
      |> assign(:entities, Entities.list_entities())

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    view_mode = Map.get(params, "view", "table")

    socket =
      socket
      |> assign(:view_mode, view_mode)

    {:noreply, socket}
  end

  def handle_event("toggle_view_mode", %{"mode" => mode}, socket) do
    base_path = current_base_path(socket)
    query = if mode != "table", do: "?view=#{mode}", else: ""

    {:noreply, push_patch(socket, to: "#{base_path}#{query}")}
  end

  def handle_event("archive_entity", %{"uuid" => uuid}, socket) do
    entity = Entities.get_entity!(uuid)

    case Entities.update_entity(entity, %{status: "archived"}) do
      {:ok, _entity} ->
        socket =
          socket
          |> assign(:entities, Entities.list_entities())
          |> put_flash(
            :info,
            gettext("Entity '%{name}' archived successfully", name: entity.display_name)
          )

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to archive entity"))}
    end
  end

  def handle_event("restore_entity", %{"uuid" => uuid}, socket) do
    entity = Entities.get_entity!(uuid)

    case Entities.update_entity(entity, %{status: "published"}) do
      {:ok, _entity} ->
        socket =
          socket
          |> assign(:entities, Entities.list_entities())
          |> put_flash(
            :info,
            gettext("Entity '%{name}' restored successfully", name: entity.display_name)
          )

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to restore entity"))}
    end
  end

  ## Live updates

  def handle_info({event, _entity_uuid}, socket)
      when event in [:entity_created, :entity_updated, :entity_deleted] do
    {:noreply, assign(socket, :entities, Entities.list_entities())}
  end

  # Helper Functions

  # Extracts the base path (without query string) from the current URL,
  # which already includes the correct locale and prefix segments.
  defp current_base_path(socket) do
    (socket.assigns[:url_path] || "") |> URI.parse() |> Map.get(:path) || "/"
  end

  @impl true
  def render(assigns) do
    ~H"""
      <div class="container flex flex-col mx-auto px-4 py-6">
        <%!-- Header Section --%>
        <.admin_page_header
          back={PhoenixKit.Utils.Routes.path("/admin/modules")}
          title={gettext("Entity Manager")}
          subtitle={gettext("Create and manage custom content types with dynamic fields")}
        />

        <%!-- Action Bar --%>
        <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-6 gap-4">
          <div>
            <h2 class="text-2xl font-semibold text-base-content">{gettext("All Entities")}</h2>
            <p class="text-base-content/70">
              {gettext("Manage custom content types and field definitions")}
            </p>
          </div>

          <div class="flex gap-2 items-center">
            <%!-- View Mode Toggle (hidden on small screens — cards are forced) --%>
            <div class="join hidden md:flex">
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

            <.link
              navigate={PhoenixKit.Utils.Routes.path("/admin/entities/new")}
              class="btn btn-primary"
            >
              <.icon name="hero-plus" class="w-4 h-4 mr-2" /> {gettext("New Entity")}
            </.link>
          </div>
        </div>

        <%!-- Entities Grid --%>
        <%= if Enum.empty?(@entities) do %>
          <%!-- Empty State --%>
          <div class="card bg-base-100 shadow-xl border-2 border-dashed border-base-300">
            <div class="card-body text-center py-12">
              <div class="text-6xl mb-4 opacity-50"><.icon name="hero-cube" class="w-6 h-6" /></div>
              <h3 class="text-2xl font-semibold text-base-content/60 mb-4">
                {gettext("No Entities Yet")}
              </h3>
              <p class="text-base-content/50 mb-6 max-w-md mx-auto">
                {gettext(
                  "Get started by creating your first custom content type. Think brands, products, team members, or any structured content you need."
                )}
              </p>
              <.link
                navigate={PhoenixKit.Utils.Routes.path("/admin/entities/new")}
                class="btn btn-primary btn-lg"
              >
                <.icon name="hero-plus" class="w-5 h-5 mr-2" /> {gettext("Create Your First Entity")}
              </.link>
            </div>
          </div>
        <% else %>
          <%!-- Table View: hidden on small screens, shown on md+ when table mode selected --%>
          <%= if @view_mode == "table" do %>
            <div class="hidden md:block">
              <.table_default variant="zebra" size="sm">
                <.table_default_header>
                  <.table_default_row>
                    <.table_default_header_cell>{gettext("Entity")}</.table_default_header_cell>
                    <.table_default_header_cell>{gettext("Status")}</.table_default_header_cell>
                    <.table_default_header_cell>{gettext("Fields")}</.table_default_header_cell>
                    <.table_default_header_cell>{gettext("Created")}</.table_default_header_cell>
                    <.table_default_header_cell>{gettext("Actions")}</.table_default_header_cell>
                  </.table_default_row>
                </.table_default_header>
                <.table_default_body>
                  <%= for entity <- @entities do %>
                    <.table_default_row>
                      <.table_default_cell>
                        <.link
                          navigate={
                            PhoenixKit.Utils.Routes.locale_aware_path(
                              assigns,
                              "/admin/entities/#{entity.name}/data"
                            )
                          }
                          class="flex items-center gap-3 hover:text-primary transition-colors cursor-pointer group"
                        >
                          <div class="text-2xl">
                            <%= if entity.icon do %>
                              <.icon name={entity.icon} class="w-6 h-6" />
                            <% else %>
                              <.icon name="hero-cube" class="w-6 h-6" />
                            <% end %>
                          </div>
                          <div>
                            <div class="font-bold">
                              {entity.display_name_plural || entity.display_name}
                            </div>
                            <div class="text-sm opacity-50">
                              <.icon name="hero-link" class="w-3 h-3 inline" />
                              {entity.name}
                            </div>
                            <%= if entity.description do %>
                              <div class="text-xs opacity-50 line-clamp-1 mt-1">
                                {entity.description}
                              </div>
                            <% end %>
                          </div>
                        </.link>
                      </.table_default_cell>
                      <.table_default_cell>
                        <.content_status_badge status={entity.status} />
                      </.table_default_cell>
                      <.table_default_cell>
                        <div class="flex items-center gap-1">
                          <.icon name="hero-list-bullet" class="w-4 h-4" />
                          <span>
                            {length(entity.fields_definition || [])}
                          </span>
                        </div>
                      </.table_default_cell>
                      <.table_default_cell>
                        <span class="text-sm">
                          {PhoenixKit.Utils.Date.format_date_with_user_format(entity.date_created)}
                        </span>
                      </.table_default_cell>
                      <.table_default_cell>
                        <div class="flex gap-2">
                          <.link
                            navigate={
                              PhoenixKit.Utils.Routes.locale_aware_path(
                                assigns,
                                "/admin/entities/#{entity.name}/data"
                              )
                            }
                            class="btn btn-xs btn-outline btn-info tooltip tooltip-bottom"
                            data-tip={gettext("Go to Data")}
                          >
                            <.icon name="hero-arrow-right" class="w-4 h-4 hidden sm:inline" />
                            <span class="sm:hidden whitespace-nowrap">{gettext("Go to Data")}</span>
                          </.link>
                          <.link
                            navigate={
                              PhoenixKit.Utils.Routes.path("/admin/entities/#{entity.uuid}/edit")
                            }
                            class="btn btn-xs btn-outline btn-info tooltip tooltip-bottom"
                            data-tip={gettext("Edit")}
                          >
                            <.icon name="hero-pencil" class="w-4 h-4 hidden sm:inline" />
                            <span class="sm:hidden whitespace-nowrap">{gettext("Edit")}</span>
                          </.link>
                          <%= if entity.status == "archived" do %>
                            <button
                              class="btn btn-xs btn-outline btn-info tooltip tooltip-bottom text-success"
                              phx-click="restore_entity"
                              phx-value-uuid={entity.uuid}
                              data-tip={gettext("Restore")}
                            >
                              <.icon name="hero-arrow-path" class="w-4 h-4 hidden sm:inline" />
                              <span class="sm:hidden whitespace-nowrap">{gettext("Restore")}</span>
                            </button>
                          <% else %>
                            <button
                              class="btn btn-xs btn-outline btn-info tooltip tooltip-bottom text-error"
                              phx-click="archive_entity"
                              phx-value-uuid={entity.uuid}
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
            </div>
          <% end %>

          <%!-- Card View: always shown on small screens, shown on md+ when card mode selected --%>
          <div class={if @view_mode == "table", do: "md:hidden", else: ""}>
            <div class="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              <%= for entity <- @entities do %>
                <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
                  <div class="card-body">
                    <div class="flex items-start justify-between mb-4">
                      <.link
                        navigate={PhoenixKit.Utils.Routes.path("/admin/entities/#{entity.name}/data")}
                        class="flex items-center hover:text-primary transition-colors cursor-pointer group"
                      >
                        <div class="text-2xl mr-3">
                          <%= if entity.icon do %>
                            <.icon name={entity.icon} class="w-6 h-6" />
                          <% else %>
                            <.icon name="hero-cube" class="w-6 h-6" />
                          <% end %>
                        </div>
                        <div>
                          <h3 class="card-title text-lg">
                            {entity.display_name_plural || entity.display_name}
                          </h3>
                          <p class="text-sm opacity-50">
                            <.icon name="hero-link" class="w-3 h-3 inline" />
                            {entity.name}
                          </p>
                        </div>
                      </.link>

                      <%!-- Status Badge --%>
                      <.content_status_badge status={entity.status} />
                    </div>

                    <%= if entity.description do %>
                      <p class="text-sm text-base-content/70 mb-4 line-clamp-2">
                        {entity.description}
                      </p>
                    <% end %>

                    <%!-- Field Count --%>
                    <div class="flex items-center justify-between text-sm text-base-content/60 mb-4">
                      <div class="flex items-center">
                        <.icon name="hero-list-bullet" class="w-4 h-4 mr-1" />
                        <span>
                          {length(entity.fields_definition || [])}
                          {if length(entity.fields_definition || []) == 1,
                            do: gettext("field"),
                            else: gettext("fields")}
                        </span>
                      </div>

                      <%= if entity.creator do %>
                        <span class="badge badge-outline badge-xs h-auto">
                          {gettext("by")} {entity.creator.email}
                        </span>
                      <% end %>
                    </div>

                    <%!-- Actions --%>
                    <div class="card-actions justify-end">
                      <.link
                        navigate={PhoenixKit.Utils.Routes.path("/admin/entities/#{entity.name}/data")}
                        class="btn btn-outline btn-sm"
                      >
                        <.icon name="hero-arrow-right" class="w-4 h-4 mr-1" /> {gettext("Go to Data")}
                      </.link>
                      <.link
                        navigate={PhoenixKit.Utils.Routes.path("/admin/entities/#{entity.uuid}/edit")}
                        class="btn btn-primary btn-sm"
                      >
                        <.icon name="hero-pencil" class="w-4 h-4 mr-1" /> {gettext("Edit")}
                      </.link>

                      <%!-- Archive/Restore Button --%>
                      <%= if entity.status == "archived" do %>
                        <button
                          class="btn btn-success btn-sm"
                          phx-click="restore_entity"
                          phx-value-uuid={entity.uuid}
                          title={gettext("Restore entity")}
                        >
                          <.icon name="hero-arrow-path" class="w-4 h-4" />
                        </button>
                      <% else %>
                        <button
                          class="btn btn-error btn-sm"
                          phx-click="archive_entity"
                          phx-value-uuid={entity.uuid}
                          title={gettext("Archive entity")}
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                        </button>
                      <% end %>
                    </div>

                    <%!-- Created Date --%>
                    <div class="text-xs text-base-content/50 mt-2 pt-2 border-t border-base-300">
                      {gettext("Created")} {PhoenixKit.Utils.Date.format_date_with_user_format(
                        entity.date_created
                      )}
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    """
  end
end
