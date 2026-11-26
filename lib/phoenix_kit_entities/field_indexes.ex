defmodule PhoenixKitEntities.FieldIndexes do
  @moduledoc """
  Opt-in typed indexes on entity fields.

  Every record of every entity lives in one `phoenix_kit_entity_data` table,
  its values in the `data` JSONB, so a filter on a field ("price under 200",
  "available from 2026-12-01") scans every row of the entity. A field
  definition can ask for an index:

      %{"type" => "number", "key" => "price", "label" => "Price", "indexed" => "numeric"}

  `"indexed"` is `"numeric"`, `"text"` or `"date"` (absent: no index). The
  index is a btree expression index on

      (entity_uuid, <schema>.phoenix_kit_entities_idx_<type>(data, '<key>'))

  built from the V2 functions (see `PhoenixKitEntities.Migrations`). Those
  are the SAME functions `PhoenixKitEntities.FieldQuery` filters with —
  `expression/3` is the one place either side gets its SQL from — so the
  planner can use the index and both always agree on the cast. A value that
  does not cast (`"abc"` in a numeric field, an impossible date) is NULL in
  the index: a dirty value never fails a write or an index build, and
  never matches a filter.

  ## Lifecycle

  Indexes are not migrations: `sync/2` makes the database match an
  entity's definitions — it creates the missing ones and drops those the
  entity no longer asks for. Outside a transaction it uses
  `CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY`, so writes to the
  table go on while an index builds; inside one (where `CONCURRENTLY`
  cannot run) it builds plainly. An interrupted concurrent build leaves an
  INVALID index; the next sync drops and rebuilds it.

  Creating, updating or deleting an entity whose indexed fields changed
  calls `schedule_sync/1`, which runs `sync/2` in a task under
  `PhoenixKit.TaskSupervisor` after the save. Set

      config :phoenix_kit_entities, field_indexes: :manual

  to skip that and call `sync/2` / `sync_all/1` yourself (from a release
  task, say). An entity with no indexed field never triggers anything, so
  an install that does not use the option sees no change.

  Each index carries a `COMMENT` naming its entity, type and key, which is
  how a sync finds the ones it owns. The names are
  `phoenix_kit_entity_data_fx_<16 hex>`, a hash of the three.
  """

  require Logger

  alias PhoenixKitEntities, as: Entities

  @types ~w(numeric text date)
  @comment_prefix "phoenix_kit_entities:field_index:"
  @name_prefix "phoenix_kit_entity_data_fx_"
  @table "phoenix_kit_entity_data"

  @type index_type :: String.t()
  @type spec :: {key :: String.t(), index_type()}

  defp repo, do: PhoenixKit.RepoHelper.repo()

  @doc "The index types a field can ask for: `numeric`, `text`, `date`."
  @spec types() :: [index_type()]
  def types, do: @types

  @doc """
  The index type a field definition asks for, or `nil`. Atoms and strings
  are accepted (`:numeric`, `"numeric"`); anything else is `nil`.
  """
  @spec index_type(map()) :: index_type() | nil
  def index_type(%{"indexed" => type}) when is_atom(type) and not is_nil(type),
    do: index_type(%{"indexed" => Atom.to_string(type)})

  def index_type(%{"indexed" => type}) when type in @types, do: type
  def index_type(_field), do: nil

  @doc """
  The type a field's values are compared as when `FieldQuery` filters on
  it: the field's own `"indexed"` type, else one derived from its field
  type (`number`/`decimal` → numeric, `date` → date, anything else →
  text). Deriving matters for an unindexed field only; an indexed one
  always uses the type its index was built with.
  """
  @spec query_type(map()) :: index_type()
  def query_type(field) do
    index_type(field) ||
      case field["type"] do
        type when type in ["number", "decimal"] -> "numeric"
        "date" -> "date"
        _ -> "text"
      end
  end

  @doc "The `{key, type}` pairs an entity's definitions ask to index, in field order."
  @spec specs(Entities.t() | map() | nil) :: [spec()]
  def specs(%{fields_definition: fields}) when is_list(fields) do
    for %{"key" => key} = field <- fields,
        is_binary(key),
        type = index_type(field),
        do: {key, type}
  end

  def specs(_), do: []

  @doc """
  The SQL expression for field `key` of `data_ref` (`"data"`, or an aliased
  `"d.data"`) read as `type` — the one source both the indexes and
  `FieldQuery` use. `key` is embedded as a quoted literal (an expression
  index only matches a query whose expression is the same constant).
  """
  @spec expression(String.t(), String.t(), index_type()) :: String.t()
  def expression(data_ref, key, type) when type in @types do
    "#{schema()}.phoenix_kit_entities_idx_#{type}(#{data_ref}, #{literal(key)})"
  end

  @doc "The full, uncut text of field `key` (what a text filter rechecks against)."
  @spec text_expression(String.t(), String.t()) :: String.t()
  def text_expression(data_ref, key) do
    "#{schema()}.phoenix_kit_entities_field_text(#{data_ref}, #{literal(key)})"
  end

  @doc "The index name for one entity, key and type."
  @spec index_name(Ecto.UUID.t(), String.t(), index_type()) :: String.t()
  def index_name(entity_uuid, key, type) do
    hash =
      :crypto.hash(:sha256, "#{entity_uuid}|#{type}|#{key}")
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    @name_prefix <> hash
  end

  @doc """
  The field indexes that exist for an entity, as
  `[%{name, key, type, valid?}]`.
  """
  @spec list(Entities.t() | Ecto.UUID.t()) :: [map()]
  def list(%{uuid: uuid}), do: list(uuid)

  def list(entity_uuid) when is_binary(entity_uuid) do
    %{rows: rows} =
      repo().query!(
        """
        SELECT c.relname, d.description, i.indisvalid
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_index i ON i.indexrelid = c.oid
        JOIN pg_description d ON d.objoid = c.oid AND d.classoid = 'pg_class'::regclass
        WHERE n.nspname = $1 AND c.relkind = 'i' AND d.description LIKE $2
        ORDER BY c.relname
        """,
        [schema(), @comment_prefix <> entity_uuid <> ":%"]
      )

    Enum.map(rows, fn [name, comment, valid?] ->
      [_, _, _, type, key] = String.split(comment, ":", parts: 5)
      %{name: name, key: key, type: type, valid?: valid?}
    end)
  end

  @doc """
  Makes the database's field indexes for `entity` match its definitions.
  Returns `{:ok, %{created: names, dropped: names}}` or `{:error, reason}`
  (the first statement that failed; indexes handled before it stay).

  Options: `:concurrently` (default: `true` outside a transaction, and
  forced `false` inside one).
  """
  @spec sync(Entities.t() | Ecto.UUID.t(), keyword()) ::
          {:ok, %{created: [String.t()], dropped: [String.t()]}} | {:error, term()}
  def sync(entity, opts \\ [])

  def sync(entity_uuid, opts) when is_binary(entity_uuid) do
    case Entities.get_entity(entity_uuid) do
      nil -> sync_specs(entity_uuid, [], opts)
      entity -> sync(entity, opts)
    end
  end

  def sync(%{uuid: uuid} = entity, opts), do: sync_specs(uuid, specs(entity), opts)

  @doc """
  `sync/2` for every entity, and drops the field indexes of entities that
  no longer exist. Returns `{:ok, %{created: n, dropped: n}}`.
  """
  @spec sync_all(keyword()) :: {:ok, %{created: integer(), dropped: integer()}} | {:error, term()}
  def sync_all(opts \\ []) do
    entities = Entities.list_entities()
    known = MapSet.new(entities, & &1.uuid)

    orphans =
      list_all_entity_uuids()
      |> Enum.reject(&MapSet.member?(known, &1))

    work = Enum.map(entities, &{&1.uuid, specs(&1)}) ++ Enum.map(orphans, &{&1, []})

    Enum.reduce_while(work, {:ok, %{created: 0, dropped: 0}}, fn
      {uuid, specs}, {:ok, acc} ->
        case sync_specs(uuid, specs, opts) do
          {:ok, %{created: c, dropped: d}} ->
            {:cont, {:ok, %{created: acc.created + length(c), dropped: acc.dropped + length(d)}}}

          {:error, _} = error ->
            {:halt, error}
        end
    end)
  end

  @doc """
  Runs `sync/2` for `entity` in the background after a save (see the
  moduledoc). Does nothing under `field_indexes: :manual`.
  """
  @spec schedule_sync(Entities.t()) :: :ok
  def schedule_sync(%{uuid: uuid}) do
    if Application.get_env(:phoenix_kit_entities, :field_indexes, :async) == :async do
      Task.Supervisor.start_child(PhoenixKit.TaskSupervisor, fn -> sync_and_log(uuid) end)
    end

    :ok
  rescue
    # No TaskSupervisor (a host that does not start core's children):
    # the save stands, the index waits for a manual sync.
    error ->
      Logger.warning("[Entities] could not schedule a field index sync: #{inspect(error)}")
      :ok
  catch
    :exit, _ -> :ok
  end

  defp sync_and_log(uuid) do
    case sync(uuid) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.error("[Entities] field index sync failed: #{inspect(reason)}")
    end
  end

  # ── internals ───────────────────────────────────────────────────────

  defp sync_specs(entity_uuid, specs, opts) do
    concurrently? = Keyword.get(opts, :concurrently, true) and not repo().in_transaction?()
    existing = list(entity_uuid)

    wanted =
      Map.new(specs, fn {key, type} -> {index_name(entity_uuid, key, type), {key, type}} end)

    # An index that is no longer wanted, or one left INVALID by an
    # interrupted concurrent build, goes; the second kind is rebuilt below.
    {to_drop, to_keep} =
      Enum.split_with(existing, &(not Map.has_key?(wanted, &1.name) or not &1.valid?))

    kept = MapSet.new(to_keep, & &1.name)
    to_create = Enum.reject(wanted, fn {name, _} -> MapSet.member?(kept, name) end)

    with {:ok, dropped} <- run_each(to_drop, &drop_index(&1.name, concurrently?)),
         {:ok, created} <-
           run_each(to_create, fn {name, {key, type}} ->
             create_index(entity_uuid, name, key, type, concurrently?)
           end) do
      {:ok, %{created: created, dropped: dropped}}
    end
  end

  defp run_each(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, done} ->
      case fun.(item) do
        {:ok, name} -> {:cont, {:ok, done ++ [name]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp create_index(entity_uuid, name, key, type, concurrently?) do
    s = schema()
    how = if concurrently?, do: "CONCURRENTLY ", else: ""

    sql =
      "CREATE INDEX #{how}IF NOT EXISTS #{name} ON #{s}.#{@table} USING btree " <>
        "(entity_uuid, (#{expression("data", key, type)}))"

    comment =
      "COMMENT ON INDEX #{s}.#{name} IS #{literal(@comment_prefix <> "#{entity_uuid}:#{type}:#{key}")}"

    with {:ok, _} <- ddl(sql, concurrently?),
         {:ok, _} <- repo().query(comment, []) do
      {:ok, name}
    end
  end

  defp drop_index(name, concurrently?) do
    how = if concurrently?, do: "CONCURRENTLY ", else: ""

    case ddl("DROP INDEX #{how}IF EXISTS #{schema()}.#{name}", concurrently?) do
      {:ok, _} -> {:ok, name}
      {:error, _} = error -> error
    end
  end

  # `in_transaction?/0` cannot see every transaction (a caller's sandbox, a
  # transaction opened on the connection by other means), so a CONCURRENTLY
  # that Postgres refuses for that reason runs again plainly.
  defp ddl(sql, concurrently?) do
    case repo().query(sql, [], timeout: :infinity) do
      {:error, %Postgrex.Error{postgres: %{code: :active_sql_transaction}}} when concurrently? ->
        repo().query(String.replace(sql, " CONCURRENTLY ", " ", global: false), [],
          timeout: :infinity
        )

      result ->
        result
    end
  end

  defp list_all_entity_uuids do
    %{rows: rows} =
      repo().query!(
        """
        SELECT DISTINCT split_part(d.description, ':', 3)
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_description d ON d.objoid = c.oid AND d.classoid = 'pg_class'::regclass
        WHERE n.nspname = $1 AND c.relkind = 'i' AND d.description LIKE $2
        """,
        [schema(), @comment_prefix <> "%"]
      )

    List.flatten(rows)
  end

  @doc false
  # A SQL string literal. `standard_conforming_strings` is on (Postgres'
  # default since 9.1), so doubling the quote is the whole escape; a NUL
  # byte cannot be in a Postgres string at all and is refused.
  @spec literal(String.t()) :: String.t()
  def literal(value) when is_binary(value) do
    if String.contains?(value, <<0>>), do: raise(ArgumentError, "NUL byte in #{inspect(value)}")
    "'" <> String.replace(value, "'", "''") <> "'"
  end

  @doc false
  @spec schema() :: String.t()
  def schema do
    prefix = Application.get_env(:phoenix_kit, :prefix) || "public"

    unless prefix =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      raise ArgumentError, "invalid schema prefix: #{inspect(prefix)}"
    end

    prefix
  end
end
