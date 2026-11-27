defmodule PhoenixKitEntities.FieldIndexRepairWorker do
  @moduledoc """
  Daily repair of the opt-in field indexes (`PhoenixKitEntities.FieldIndexes`),
  scheduled by the module's `oban_crons/0`.

  A sync runs after a save that changes which fields are indexed; one that
  failed (an interrupted concurrent build, a lock timeout) would otherwise
  wait for the next such save. This job runs `FieldIndexes.sync_all/1` with
  `repair_only: true`: it builds the indexes a definition asks for that are
  missing or INVALID and never drops anything else. With nothing wrong it
  changes nothing. With the module switched off it does nothing.

  Runs in core's `default` queue, one at a time.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      fields: [:worker],
      keys: [],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias PhoenixKitEntities.FieldIndexes

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if PhoenixKitEntities.enabled?(),
      do: FieldIndexes.sync_all(repair_only: true) |> outcome(),
      else: :ok
  end

  # Every entity was tried; any failure makes the job retry (Oban backoff).
  defp outcome({:ok, %{failed: failed}}) when failed > 0,
    do: {:error, {:field_index_repair_failed, failed}}

  defp outcome({:ok, %{created: 0}}), do: :ok

  defp outcome({:ok, %{created: n, dropped: d}}) do
    Logger.info("[Entities] field index repair rebuilt #{n} index(es), dropped #{d} invalid")
    :ok
  end

  defp outcome({:error, _} = error), do: error
end
