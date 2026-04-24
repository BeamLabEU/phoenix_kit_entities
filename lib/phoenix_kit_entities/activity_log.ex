defmodule PhoenixKitEntities.ActivityLog do
  @moduledoc false
  # Shared activity-logging helper for entity + entity_data mutations.
  # Wraps `PhoenixKit.Activity.log/1` with the "entities" module key.
  #
  # The core Activity context is optional — parent apps that don't install it
  # will simply skip logging. We guard with `Code.ensure_loaded?/1` and a
  # try/rescue so a logging failure never propagates back to the caller.

  require Logger

  @module_key "entities"

  @doc """
  Logs an activity entry with `module: "entities"` injected.

  Never raises — swallows any error from the Activity context with a Logger
  warning so the caller's primary mutation isn't affected.
  """
  @spec log(map()) :: :ok
  def log(attrs) when is_map(attrs) do
    if Code.ensure_loaded?(PhoenixKit.Activity) do
      try do
        PhoenixKit.Activity.log(Map.put(attrs, :module, @module_key))
      rescue
        error ->
          Logger.warning(
            "PhoenixKitEntities activity log failed: " <>
              "#{Exception.message(error)} — attrs=" <>
              inspect(Map.take(attrs, [:action, :resource_type, :resource_uuid]))
          )
      end
    end

    :ok
  end

  @doc """
  Runs `op_fun` and, on `{:ok, record}`, logs an activity entry built from
  `attrs_fun.(record)`. Collapses the common `case Repo.insert(...) do ...`
  shape used in each mutation path.

  `op_fun` returns `{:ok, term} | {:error, term}`; `attrs_fun` only runs on
  success.
  """
  @spec with_log((-> {:ok, term()} | {:error, term()}), (term() -> map())) ::
          {:ok, term()} | {:error, term()}
  def with_log(op_fun, attrs_fun) when is_function(op_fun, 0) and is_function(attrs_fun, 1) do
    case op_fun.() do
      {:ok, record} = ok ->
        log(attrs_fun.(record))
        ok

      {:error, _} = err ->
        err
    end
  end
end
