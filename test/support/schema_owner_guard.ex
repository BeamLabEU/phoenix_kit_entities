defmodule PhoenixKitEntities.Test.SchemaOwnerGuard do
  @moduledoc """
  I067: `config/test.exs` lets `PGDATABASE` override this repo's isolated
  test DB name. Ecto.Migrator's `schema_migrations` bookkeeping table is
  keyed only by version number, with no package namespace — pointing
  `PGDATABASE` at a database another package's migrator already owns makes
  same-numbered migrations from this package silently get treated as
  "already applied" and never run (confirmed live via `Ecto.Migrator.run/4`
  in the I067 recon, same mechanism as `phoenix_kit_crm`'s copy of this
  module). This stamps a `COMMENT ON TABLE schema_migrations` marker naming
  the owning package, and refuses to proceed if a stamped marker names
  someone else.

  `stamp!/1` runs UNCONDITIONALLY, on every boot, `PGDATABASE` or not.
  Marking only under `PGDATABASE` would leave a package's own default,
  isolated DB unmarked forever — and that default DB, with its predictable
  name on the same instance, is the single most likely target for a later
  `PGDATABASE` override. Stamping only there would catch the SECOND
  collision, never the first, silently. `check!/1` still only matters
  under `PGDATABASE` — that's the only time a name someone else's migrator
  already owns can be in play at all.
  """

  @package "phoenix_kit_entities"

  defmodule OwnerMismatch do
    defexception [:message]
  end

  @doc "Raises `OwnerMismatch` if the DB's schema_migrations marker names a different package."
  @spec check!((String.t() -> %{rows: list()})) :: :ok
  def check!(query_fn) do
    if System.get_env("PGDATABASE") do
      case owner(query_fn) do
        nil ->
          :ok

        owner when owner == @package ->
          :ok

        other ->
          raise OwnerMismatch,
            message: """
            PGDATABASE points at a database whose migration history belongs to \
            #{other}, not #{@package} — this would silently corrupt or skip \
            migrations. Use an isolated test DB, or a fresh one, instead.\
            """
      end
    else
      :ok
    end
  end

  @doc "Stamps this package as schema_migrations' owner. Unconditional — see moduledoc."
  @spec stamp!((String.t() -> %{rows: list()})) :: :ok
  def stamp!(query_fn) do
    query_fn.("COMMENT ON TABLE schema_migrations IS '#{@package}'")
    :ok
  end

  defp owner(query_fn) do
    %{rows: [[table_exists?]]} =
      query_fn.(
        "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'schema_migrations')"
      )

    if table_exists? do
      %{rows: [[comment]]} =
        query_fn.("SELECT obj_description('schema_migrations'::regclass, 'pg_class')")

      comment
    else
      nil
    end
  end
end
