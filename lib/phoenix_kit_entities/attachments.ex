defmodule PhoenixKitEntities.Attachments do
  @moduledoc """
  Scope folder for file/image fields of an entity type:

      config :phoenix_kit_entities, :attachments_parent_folder, {MyApp.Media, :parent_for}

  called as `parent_for(:entity_file, actor_uuid, %{entity_name: name})` (or `/2`),
  returning `{:ok, folder_uuid}` or `nil` (no scope, today's behaviour).
  """
  require Logger

  @spec scope_folder(String.t(), String.t() | nil) :: String.t() | nil
  def scope_folder(entity_name, actor_uuid) do
    case Application.get_env(:phoenix_kit_entities, :attachments_parent_folder) do
      {mod, fun} when is_atom(mod) and is_atom(fun) ->
        mod
        |> invoke_hook(fun, actor_uuid, entity_name)
        |> folder_uuid()

      _ ->
        nil
    end
  rescue
    error ->
      Logger.warning("[Entities] scope folder hook failed: #{inspect(error)}")
      nil
  end

  defp invoke_hook(mod, fun, actor_uuid, entity_name) do
    cond do
      Code.ensure_loaded?(mod) and function_exported?(mod, fun, 3) ->
        apply(mod, fun, [:entity_file, actor_uuid, %{entity_name: entity_name}])

      Code.ensure_loaded?(mod) and function_exported?(mod, fun, 2) ->
        apply(mod, fun, [:entity_file, actor_uuid])

      true ->
        nil
    end
  end

  defp folder_uuid({:ok, uuid}) when is_binary(uuid), do: uuid
  defp folder_uuid(_), do: nil
end
