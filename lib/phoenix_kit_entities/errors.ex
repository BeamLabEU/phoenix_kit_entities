defmodule PhoenixKitEntities.Errors do
  @moduledoc """
  Central mapping from error atoms (returned by the Entities module's
  public API) to translated human-readable strings.

  Keeping the API layer locale-agnostic means callers can pattern-match
  on atoms and decide their own presentation. Anything user-facing
  (flash messages, error banners) goes through `message/1` which wraps
  each mapping in `gettext/1` using the `PhoenixKitWeb.Gettext` backend.

  ## Supported reason shapes

    * plain atoms — `:cannot_remove_primary`, `:not_multilang`,
      `:entity_not_found`, etc.
    * tagged tuples — `{:invalid_field_type, type}`,
      `{:requires_options, type}`, `{:missing_required_keys, [keys]}`,
      `{:user_entity_limit_reached, max}`. The dynamic part is
      interpolated via `gettext` bindings so the wording lives in core
      `.po` files.
    * strings — passed through unchanged (legacy / pre-existing
      messages already translated at the call site)
    * anything else — rendered as `"Unexpected error: <inspect>"` via
      gettext so nothing silently surfaces a raw struct

  ## Example

      iex> PhoenixKitEntities.Errors.message(:cannot_remove_primary)
      "Cannot remove the primary language."

      iex> PhoenixKitEntities.Errors.message({:invalid_field_type, "blob"})
      "Invalid field type: blob"
  """

  use Gettext, backend: PhoenixKitWeb.Gettext

  @typedoc """
  Plain atoms returned by the Entities public API.
  """
  @type error_atom ::
          :cannot_remove_primary
          | :not_multilang
          | :entity_not_found
          | :not_found
          | :invalid_format
          | :unexpected

  @typedoc """
  Tagged tuples carrying interpolation context.
  """
  @type tagged_error ::
          {:invalid_field_type, String.t()}
          | {:requires_options, String.t()}
          | {:missing_required_keys, [String.t()]}
          | {:user_entity_limit_reached, non_neg_integer()}

  @doc """
  Translates an error reason (atom, tagged tuple, or binary) into a
  user-facing string via gettext.
  """
  @spec message(term()) :: String.t()
  def message(:cannot_remove_primary), do: gettext("Cannot remove the primary language.")
  def message(:not_multilang), do: gettext("Multi-language support is not enabled.")
  def message(:entity_not_found), do: gettext("Entity not found.")
  def message(:not_found), do: gettext("Record not found.")
  def message(:invalid_format), do: gettext("Invalid format.")
  def message(:unexpected), do: gettext("An unexpected error occurred.")

  def message({:invalid_field_type, type}) when is_binary(type) do
    gettext("Invalid field type: %{type}", type: type)
  end

  def message({:requires_options, type}) when is_binary(type) do
    gettext("Field type '%{type}' requires options", type: type)
  end

  def message({:missing_required_keys, keys}) when is_list(keys) do
    gettext("Missing required keys: %{keys}", keys: Enum.join(keys, ", "))
  end

  def message({:user_entity_limit_reached, max}) when is_integer(max) do
    gettext("You have reached the maximum limit of %{max} entities", max: max)
  end

  def message(reason) when is_binary(reason), do: reason

  def message(reason) do
    gettext("Unexpected error: %{reason}", reason: inspect(reason))
  end
end
