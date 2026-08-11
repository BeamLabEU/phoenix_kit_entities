defmodule PhoenixKitEntities.Web.ProjectDataLive do
  @moduledoc """
  The entities **Data** tab for the `phoenix_kit_projects` hub — this
  module's `phoenix_kit_project_extensions/0` contribution (see that
  function in `PhoenixKitEntities`).

  Rendered by the projects hub via `live_render` with the hub's
  embed-session contract: `"project_uuid"`, `"config"` (`entity_uuid`
  links ONE entity to the project), `"current_user_uuid"` / `"locale"`.
  Linkage is CONFIG-based — no FK, no dependency on the projects package;
  the admin pastes the entity uuid in the project's Modules panel (the
  unconfigured state lists the candidates to copy from).

  Read-only: records list with status/date + link-outs to the entities
  admin (records are name-routed — `/admin/entities/<name>/data/...`).
  Off-router-mountable: no `handle_params/3` (the hub's hard requirement).
  """

  use Phoenix.LiveView
  use Gettext, backend: PhoenixKitEntities.Gettext

  alias PhoenixKit.Utils.Routes
  alias PhoenixKitEntities.EntityData

  @records_limit 50

  @impl true
  def mount(_params, session, socket) do
    entity_uuid = get_in(session, ["config", "entity_uuid"])
    entity = entity_uuid && safe(fn -> PhoenixKitEntities.get_entity(entity_uuid) end)

    {records, total} =
      if entity do
        records = safe(fn -> EntityData.list_by_entity(entity.uuid) end) || []
        {Enum.take(records, @records_limit), length(records)}
      else
        {[], 0}
      end

    candidates =
      if entity, do: [], else: safe(fn -> PhoenixKitEntities.list_active_entities() end) || []

    {:ok,
     assign(socket,
       project_uuid: session["project_uuid"],
       entity: entity,
       records: records,
       total: total,
       candidates: candidates
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <%= if @entity do %>
        <div class="flex items-center gap-3">
          <span class={"#{@entity.icon || "hero-cube-transparent"} w-5 h-5 opacity-70"}></span>
          <div class="min-w-0 grow">
            <h3 class="font-semibold truncate">{@entity.display_name_plural || @entity.display_name}</h3>
            <p class="text-xs opacity-60">{records_label(@total)}</p>
          </div>
          <.link
            navigate={Routes.path("/admin/entities/#{@entity.name}/data/new")}
            class="btn btn-primary btn-sm gap-1"
          >
            {gettext("New record")}
          </.link>
          <.link
            navigate={Routes.path("/admin/entities/#{@entity.name}/data")}
            class="btn btn-ghost btn-sm gap-1"
          >
            {gettext("Open in Entities")}
          </.link>
        </div>

        <%= if @records == [] do %>
          <div class="card border border-dashed border-base-300 bg-base-100">
            <div class="card-body items-center text-center py-8">
              <p class="text-sm opacity-70">{gettext("No records yet.")}</p>
            </div>
          </div>
        <% else %>
          <div class="overflow-x-auto rounded-lg border border-base-200">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Title")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Updated")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={record <- @records} class="hover:bg-base-200/40">
                  <td class="max-w-64">
                    <.link
                      navigate={Routes.path("/admin/entities/#{@entity.name}/data/#{record.uuid}")}
                      class="link link-hover font-medium truncate block"
                    >
                      {record.title}
                    </.link>
                  </td>
                  <td>
                    <span class={["badge badge-sm", status_class(record.status)]}>
                      {PhoenixKitEntities.Web.DataNavigator.status_label(record.status)}
                    </span>
                  </td>
                  <td class="text-xs opacity-60 whitespace-nowrap">
                    {format_date(record.date_updated)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@total > length(@records)} class="text-xs opacity-50">
            {gettext("Showing %{shown} of %{total} — the full list lives in the Entities admin.",
              shown: length(@records),
              total: @total
            )}
          </p>
        <% end %>
      <% else %>
        <div class="card border border-dashed border-base-300 bg-base-100">
          <div class="card-body py-6 gap-2">
            <p class="text-sm opacity-70 text-center">
              {gettext("No entity linked to this project yet.")}
            </p>
            <p class="text-xs opacity-50 text-center">
              {gettext(
                "Paste an entity UUID into this tab's settings in the project's Modules & features panel."
              )}
            </p>
            <div :if={@candidates != []} class="mt-2">
              <p class="text-xs font-semibold opacity-60 mb-1">{gettext("Available entities:")}</p>
              <div class="flex flex-col gap-1">
                <div
                  :for={candidate <- @candidates}
                  class="flex items-baseline gap-2 text-xs bg-base-200/60 rounded px-2 py-1"
                >
                  <span class="font-medium shrink-0">{candidate.display_name}</span>
                  <code class="opacity-60 truncate">{candidate.uuid}</code>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp records_label(0), do: gettext("No records")
  defp records_label(n), do: ngettext("%{count} record", "%{count} records", n)

  defp status_class("published"), do: "badge-success"
  defp status_class("draft"), do: "badge-ghost"
  defp status_class("archived"), do: "badge-warning"
  defp status_class(_), do: "badge-ghost"

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%b %-d, %Y")
  defp format_date(_), do: "—"

  # An entities DB hiccup degrades the tab to its empty state — a
  # contributed extension tab must never crash the host project page.
  defp safe(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
