defmodule PhoenixKitEntities.Components.FieldInput do
  @moduledoc """
  Control-only inline renderer for ONE entity field — the embeddable
  primitive under `FormBuilder.build_field/3`'s full form blocks. Hosts
  that lay records out their own way (compact rows, table cells, chips)
  render `<.field_input>` per field and keep full ownership of layout,
  labels, and persistence, while every field type — including ones added
  to entities later — renders correctly without host changes.

  ## The save contract

  The host wraps its inputs in a `<form phx-change="...">` it owns
  (include hidden inputs for row identity — a record uuid — and read
  `_target` to know which field changed):

    * **Typed inputs** (text, textarea, email, url, rich_text, number,
      date) carry `phx-debounce="blur"`, so the form's change event
      fires on blur/enter — not per keystroke.
    * **Discrete inputs** (boolean toggle, select, radio, checkbox
      group) fire immediately. Booleans pair the checkbox with a hidden
      `"false"` input and checkbox groups a hidden `""`, so the change
      payload always carries the key even when everything is unticked.
    * **Media references** (image, video) are not form inputs at all:
      they render the current file (thumbnail for images) plus
      Choose/Clear buttons that push the host's `on_pick`/`on_clear`
      events with `phx-value-field={field key}` and any `pick_params`.
      The host opens its media picker (e.g. core's `MediaSelectorModal`)
      and writes the chosen storage file uuid through its own save path.

  Cast the change payload with `PhoenixKitEntities.FormBuilder.cast_field/2`
  before persisting — it applies the same per-type coercion and
  validation the full form pipeline uses.

  Nested forms are invalid HTML: this component renders bare controls
  precisely so it can live inside whatever form (or none) the host has;
  the host is responsible for the form context.

  ## Example

      <form id={"row-\#{value.uuid}"} phx-change="extras_changed">
        <input type="hidden" name="uuid" value={value.uuid} />
        <.field_input
          :for={field <- @entity.fields_definition}
          field={field}
          name={"extras[\#{field["key"]}]"}
          value={value.data[field["key"]]}
          size="xs"
          on_pick="pick_extra_media"
          on_clear="clear_extra_media"
          pick_params={%{"uuid" => value.uuid}}
        />
      </form>
  """

  use Phoenix.Component
  use Gettext, backend: PhoenixKitEntities.Gettext

  import PhoenixKitWeb.Components.Core.Icon, only: [icon: 1]

  alias PhoenixKit.Modules.Storage.URLSigner

  @doc """
  Renders the control for one field definition. See the moduledoc for
  the save contract per field-type family.
  """
  attr(:field, :map, required: true, doc: "one fields_definition entry")
  attr(:name, :string, required: true, doc: "form input name, e.g. extras[price]")
  attr(:value, :any, default: nil)
  attr(:id, :string, default: nil, doc: "derived from name when absent")
  attr(:size, :string, default: "sm", values: ~w(xs sm md))
  attr(:disabled, :boolean, default: false)

  attr(:on_pick, :string,
    default: nil,
    doc: "event pushed by the image/video Choose button (required for those types)"
  )

  attr(:on_clear, :string,
    default: nil,
    doc: "event pushed by the image/video Clear button (hidden when absent)"
  )

  attr(:pick_params, :map,
    default: %{},
    doc: "extra phx-value-* params on the pick/clear buttons (row identity)"
  )

  def field_input(%{field: %{"type" => type}} = assigns) do
    assigns =
      assigns
      |> assign(:type, type)
      |> assign_new(:input_id, fn %{id: id, name: name} ->
        id || "field-input-" <> String.replace(name, ~r/[^A-Za-z0-9_-]+/, "-")
      end)
      |> assign(:pick_attrs, pick_attrs(assigns))

    render_input(assigns)
  end

  defp render_input(%{type: t} = assigns) when t in ["text", "email", "url"] do
    ~H"""
    <input
      type={@type}
      id={@input_id}
      name={@name}
      value={@value}
      placeholder={@field["placeholder"]}
      disabled={@disabled}
      phx-debounce="blur"
      class={["input input-bordered bg-base-100", size_class("input", @size)]}
    />
    """
  end

  defp render_input(%{type: t} = assigns) when t in ["textarea", "rich_text"] do
    ~H"""
    <textarea
      id={@input_id}
      name={@name}
      placeholder={@field["placeholder"]}
      disabled={@disabled}
      rows="2"
      phx-debounce="blur"
      class={["textarea textarea-bordered bg-base-100", size_class("textarea", @size)]}
    >{@value}</textarea>
    """
  end

  defp render_input(%{type: "number"} = assigns) do
    ~H"""
    <input
      type="number"
      id={@input_id}
      name={@name}
      value={@value}
      min={@field["min"]}
      max={@field["max"]}
      step={@field["step"] || "any"}
      placeholder={@field["placeholder"]}
      disabled={@disabled}
      phx-debounce="blur"
      class={["input input-bordered bg-base-100", size_class("input", @size)]}
    />
    """
  end

  defp render_input(%{type: "date"} = assigns) do
    ~H"""
    <input
      type="date"
      id={@input_id}
      name={@name}
      value={@value}
      disabled={@disabled}
      phx-debounce="blur"
      class={["input input-bordered bg-base-100", size_class("input", @size)]}
    />
    """
  end

  # The hidden "false" makes an untick still submit the key — without
  # it the change payload simply omits unchecked checkboxes and the
  # host cannot distinguish "turned off" from "not present".
  defp render_input(%{type: "boolean"} = assigns) do
    ~H"""
    <span class="inline-flex items-center">
      <input type="hidden" name={@name} value="false" />
      <input
        type="checkbox"
        id={@input_id}
        name={@name}
        value="true"
        checked={@value in [true, "true"]}
        disabled={@disabled}
        class={["toggle", size_class("toggle", @size)]}
      />
    </span>
    """
  end

  defp render_input(%{type: "select"} = assigns) do
    ~H"""
    <select
      id={@input_id}
      name={@name}
      disabled={@disabled}
      class={["select select-bordered bg-base-100", size_class("select", @size)]}
    >
      <option value="">{gettext("—")}</option>
      <option
        :for={option <- @field["options"] || []}
        value={option}
        selected={to_string(@value) == to_string(option)}
      >
        {option}
      </option>
    </select>
    """
  end

  # Radios submit nothing when none is picked — the hidden "" keeps the
  # key present, same trick as boolean above.
  defp render_input(%{type: "radio"} = assigns) do
    ~H"""
    <span class="inline-flex flex-wrap items-center gap-2">
      <input type="hidden" name={@name} value="" />
      <label
        :for={option <- @field["options"] || []}
        class="inline-flex items-center gap-1 cursor-pointer text-sm"
      >
        <input
          type="radio"
          name={@name}
          value={option}
          checked={to_string(@value) == to_string(option)}
          disabled={@disabled}
          class={["radio", size_class("radio", @size)]}
        />
        {option}
      </label>
    </span>
    """
  end

  defp render_input(%{type: "checkbox"} = assigns) do
    assigns = assign(assigns, :selected, List.wrap(assigns.value))

    ~H"""
    <span class="inline-flex flex-wrap items-center gap-2">
      <input type="hidden" name={@name} value="" />
      <label
        :for={option <- @field["options"] || []}
        class="inline-flex items-center gap-1 cursor-pointer text-sm"
      >
        <input
          type="checkbox"
          name={@name <> "[]"}
          value={option}
          checked={option in @selected}
          disabled={@disabled}
          class={["checkbox", size_class("checkbox", @size)]}
        />
        {option}
      </label>
    </span>
    """
  end

  defp render_input(%{type: t} = assigns) when t in ["image", "video"] do
    ~H"""
    <span class="inline-flex items-center gap-2">
      <%= if is_binary(@value) and @value != "" do %>
        <img
          :if={@type == "image"}
          src={URLSigner.signed_url(@value, "thumbnail")}
          alt={@field["label"]}
          class={["object-cover rounded border border-base-content/10", thumb_class(@size)]}
        />
        <.icon :if={@type == "video"} name="hero-video-camera" class="w-5 h-5 text-base-content/60" />
      <% end %>
      <button
        :if={@on_pick}
        type="button"
        phx-click={@on_pick}
        phx-value-field={@field["key"]}
        disabled={@disabled}
        class={["btn btn-outline", size_class("btn", @size)]}
        {@pick_attrs}
      >
        <.icon
          name={if @type == "image", do: "hero-photo", else: "hero-video-camera"}
          class="w-3.5 h-3.5"
        />
        {if is_binary(@value) and @value != "",
          do: gettext("Change"),
          else: gettext("Choose")}
      </button>
      <button
        :if={@on_clear && is_binary(@value) && @value != ""}
        type="button"
        phx-click={@on_clear}
        phx-value-field={@field["key"]}
        disabled={@disabled}
        class={["btn btn-ghost px-1", size_class("btn", @size)]}
        title={gettext("Clear")}
        {@pick_attrs}
      >
        <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
      </button>
    </span>
    """
  end

  # heading carries no data; unknown types (relation, future additions
  # this version doesn't know) degrade to a muted note instead of
  # crashing the host's page.
  defp render_input(%{type: "heading"} = assigns), do: ~H""

  defp render_input(assigns) do
    ~H"""
    <span class="text-xs text-base-content/40 italic">
      {gettext("Unsupported field type: %{type}", type: @type)}
    </span>
    """
  end

  defp pick_attrs(%{pick_params: params}) when is_map(params) do
    Map.new(params, fn {k, v} -> {"phx-value-#{k}", v} end)
  end

  defp pick_attrs(_), do: %{}

  defp size_class(base, "xs"), do: base <> "-xs"
  defp size_class(base, "sm"), do: base <> "-sm"
  defp size_class(_base, _md), do: nil

  defp thumb_class("xs"), do: "w-6 h-6"
  defp thumb_class("sm"), do: "w-8 h-8"
  defp thumb_class(_), do: "w-12 h-12"
end
