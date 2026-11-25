defmodule PhoenixKitEntities.PublicFormTurnstile do
  @moduledoc """
  Cloudflare Turnstile for an entity's public form, built on core's website
  integrations (`PhoenixKit.Integrations.Turnstile`, core 3.7.0+).

  Per entity, in `settings`:

    * `"public_form_turnstile"` — the switch (default off).
    * `"public_form_turnstile_connection"` — the UUID of a verified
      Cloudflare Turnstile connection (Settings → Integrations).
    * `"public_form_turnstile_action"` — what a failed check does, one of
      the security actions every other check uses (default `"reject_error"`).

  The connection belongs to the entity, so this is independent of the
  Authorization page's switch, which only protects core's own auth forms.

  ## Policy

    * No token, or a token Cloudflare refuses: the check is triggered and the
      configured action applies.
    * Cloudflare gives no verdict (`:unavailable`): fail closed, with a
      "try again in a few minutes" message — the action applies as well, except
      that `reject_silent` becomes `reject_error`, because a silent fake
      success would swallow a real visitor's message over an outage that is not
      theirs.
    * The switch is on but the connection is missing, was removed, or no
      longer verifies (`:not_configured`): the form is **not** checked and the
      request is let through with a logged error. This is what core does for
      its auth forms: the widget is hidden in that state, so refusing every
      submit would lock the form for everyone, with nothing on the page to
      fix. The builder shows a warning while the option is on and the
      connection is not usable.
  """

  alias PhoenixKit.Integrations
  alias PhoenixKit.Integrations.Turnstile, as: Cloudflare

  require Logger

  @type status :: :off | :ready | :no_connections | :no_selection | :stale_selection

  @doc "Whether the entity's settings turn Turnstile on."
  @spec enabled?(map() | nil) :: boolean()
  def enabled?(settings), do: get(settings, "public_form_turnstile") == true

  @doc "The selected connection UUID, or nil."
  @spec connection(map() | nil) :: String.t() | nil
  def connection(settings) do
    case get(settings, "public_form_turnstile_connection") do
      uuid when is_binary(uuid) and uuid != "" -> uuid
      _ -> nil
    end
  end

  @doc "Verified website Turnstile connections, as `{uuid, name}`."
  @spec choices() :: [{String.t(), String.t()}]
  def choices, do: Integrations.connected_choices(:turnstile, :system)

  @doc "The name of the form field the widget fills."
  @spec response_field() :: String.t()
  def response_field, do: Cloudflare.response_field()

  @doc """
  The public site key the form's widget renders with, or nil when the option
  is off or its connection cannot verify (the widget is then hidden).
  """
  @spec site_key(map() | nil) :: String.t() | nil
  def site_key(settings) do
    with true <- enabled?(settings),
         uuid when is_binary(uuid) <- connection(settings) do
      Cloudflare.site_key(uuid)
    else
      _ -> nil
    end
  end

  @doc """
  What the builder should tell the admin, given the connections `choices/0`
  returned: `:off`, `:ready`, or why a switched-on form is not protected.
  """
  @spec status(map() | nil, [{String.t(), String.t()}]) :: status()
  def status(settings, choices) do
    cond do
      not enabled?(settings) -> :off
      choices == [] -> :no_connections
      is_nil(connection(settings)) -> :no_selection
      Enum.any?(choices, fn {uuid, _name} -> uuid == connection(settings) end) -> :ready
      true -> :stale_selection
    end
  end

  @doc """
  Checks the token a submit carried. `:ok` also covers an option that is off
  and a connection that cannot verify (see the moduledoc).
  """
  @spec verify(map() | nil, term(), String.t() | nil) ::
          :ok | {:error, :missing | :rejected | :unavailable}
  def verify(settings, token, ip_address) do
    with true <- enabled?(settings),
         uuid when is_binary(uuid) <- connection(settings) do
      uuid |> Cloudflare.verify(token, ip_address) |> unconfigured_passes()
    else
      false ->
        :ok

      nil ->
        log_unprotected()
        :ok
    end
  end

  defp unconfigured_passes({:error, :not_configured}) do
    log_unprotected()
    :ok
  end

  defp unconfigured_passes(verdict), do: verdict

  defp log_unprotected do
    Logger.error(
      "[PublicFormTurnstile] Turnstile is switched on for a public form but its " <>
        "connection cannot verify tokens, so this submission was not checked"
    )
  end

  defp get(settings, key) when is_map(settings), do: Map.get(settings, key)
  defp get(_settings, _key), do: nil
end
