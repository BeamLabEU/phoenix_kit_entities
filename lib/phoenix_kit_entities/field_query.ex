defmodule PhoenixKitEntities.FieldQuery do
  @moduledoc """
  Filters an entity's records by field values, comparing each value as the
  type the field is indexed with (`PhoenixKitEntities.FieldIndexes`).

      FieldQuery.list(entity, [{"price", :lte, 200}, {"city", :eq, "Tallinn"}],
        order_by: {"price", :asc}, limit: 20)

  The value of a field is read from the primary language of a multilang
  record, else from the flat data. Each filter compares it as numeric, text
  or date — the field's `"indexed"` type, else one derived from its field
  type (`FieldIndexes.query_type/1`) — through exactly the SQL expression
  the field's index is built on (`FieldIndexes.expression/3`), so an indexed
  field's filter uses its index. A value that does not cast is NULL and
  matches nothing; it never raises.

  Operators: `:eq`, `:neq`, `:lt`, `:lte`, `:gt`, `:gte`, `:between`
  (`{low, high}`, inclusive), `:in` (a list), `:is_nil`, `:not_nil`.
  `:neq` (like SQL's `<>`) leaves out records that have no value for the
  field; add `{key, :is_nil}` in a separate query for those.
  Text compares only with `:eq`, `:neq`, `:in`, `:is_nil` and `:not_nil` —
  the text index holds the first 255 characters, so an equality is
  rechecked against the full value, and an order on text is by those
  characters.

  Options: `:status` (one status or a list), `:include_trashed` (default
  `false`), `:order_by` (`{key, :asc | :desc}`; default the records'
  position), `:limit` (default 100, at most 1000), `:offset`, `:lang`
  (resolves the returned records like `EntityData.list_by_entity/2`).
  """

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.{EntityData, FieldIndexes}

  import Ecto.Query, only: [from: 2]

  @max_limit 1000
  @default_limit 100
  @text_ops [:eq, :neq, :in, :is_nil, :not_nil]
  @ops [:eq, :neq, :lt, :lte, :gt, :gte, :between, :in, :is_nil, :not_nil]

  @type op :: :eq | :neq | :lt | :lte | :gt | :gte | :between | :in | :is_nil | :not_nil
  @type filter :: {String.t(), op(), term()} | {String.t(), :is_nil | :not_nil}

  defp repo, do: PhoenixKit.RepoHelper.repo()

  @doc """
  The records of `entity` (a struct, uuid or name) matching every filter,
  in the requested order. `{:error, reason}` for an unknown entity
  (`:entity_not_found`), a key the entity does not define
  (`{:unknown_field, key}`), a non-integer `:limit`/`:offset`
  (`{:invalid_option, key}`), an operator the field's type does not take
  (`{:invalid_operator, key, op}`) or a value that does not cast to it
  (`{:invalid_value, key}`), and `{:error, :standard_conforming_strings_off}`
  on a connection that would misread the quoted keys.
  """
  @spec list(Entities.t() | String.t(), [filter()], keyword()) ::
          {:ok, [EntityData.t()]} | {:error, term()}
  def list(entity, filters, opts \\ []) when is_list(filters) do
    with {:ok, entity} <- fetch_entity(entity),
         {:ok, sql, params} <- build(entity, filters, opts) do
      %{rows: rows} = repo().query!(sql, params)
      uuids = Enum.map(rows, fn [uuid] -> Ecto.UUID.load!(uuid) end)
      {:ok, load(uuids, opts)}
    end
  end

  @doc "Like `list/3`, but the number of matching records (`:limit`/`:order_by` ignored)."
  @spec count(Entities.t() | String.t(), [filter()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def count(entity, filters, opts \\ []) when is_list(filters) do
    with {:ok, entity} <- fetch_entity(entity),
         :ok <- FieldIndexes.check_literals(),
         {:ok, where, params} <- where_clause(entity, filters, opts) do
      sql =
        "SELECT count(*) FROM #{FieldIndexes.schema()}.phoenix_kit_entity_data d WHERE #{where}"

      %{rows: [[n]]} = repo().query!(sql, params)
      {:ok, n}
    end
  end

  @doc """
  The SQL `list/3` runs, with its parameters — for an `EXPLAIN`, or a test
  that the planner picks the field's index.
  """
  @spec build(Entities.t(), [filter()], keyword()) ::
          {:ok, String.t(), list()} | {:error, term()}
  def build(%{} = entity, filters, opts \\ []) do
    with :ok <- FieldIndexes.check_literals(),
         {:ok, where, params} <- where_clause(entity, filters, opts),
         {:ok, order} <- order_clause(entity, opts[:order_by]),
         {:ok, limit} <- integer_opt(opts, :limit, @default_limit),
         {:ok, offset} <- integer_opt(opts, :offset, 0) do
      limit = limit |> min(@max_limit) |> max(0)
      offset = max(offset, 0)

      sql =
        "SELECT d.uuid FROM #{FieldIndexes.schema()}.phoenix_kit_entity_data d " <>
          "WHERE #{where} ORDER BY #{order} LIMIT #{limit} OFFSET #{offset}"

      {:ok, sql, params}
    end
  end

  # ── building ────────────────────────────────────────────────────────

  # LIMIT and OFFSET are written into the SQL, so only an integer gets
  # there (a string would be SQL).
  defp integer_opt(opts, key, default) do
    case Keyword.get(opts, key, default) do
      n when is_integer(n) -> {:ok, n}
      nil -> {:ok, default}
      _ -> {:error, {:invalid_option, key}}
    end
  end

  defp where_clause(entity, filters, opts) do
    base = ["d.entity_uuid = $1::uuid"]
    params = [Ecto.UUID.dump!(entity.uuid)]
    {base, params} = status_clause(base, params, opts)
    fields = Map.new(entity.fields_definition || [], &{&1["key"], &1})

    Enum.reduce_while(filters, {:ok, base, params}, fn filter, {:ok, clauses, params} ->
      case filter_clause(fields, filter, params) do
        {:ok, clause, params} -> {:cont, {:ok, clauses ++ [clause], params}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, clauses, params} -> {:ok, Enum.join(clauses, " AND "), params}
      error -> error
    end
  end

  defp status_clause(clauses, params, opts) do
    clauses =
      if opts[:include_trashed], do: clauses, else: clauses ++ ["d.status <> 'trashed'"]

    case opts[:status] do
      nil ->
        {clauses, params}

      statuses ->
        n = length(params) + 1
        statuses = statuses |> List.wrap() |> Enum.map(&status_text/1)
        {clauses ++ ["d.status = ANY($#{n}::text[])"], params ++ [statuses]}
    end
  end

  # Anything that is not a status name matches no record.
  defp status_text(status) when is_binary(status), do: status
  defp status_text(status) when is_atom(status) and not is_nil(status), do: Atom.to_string(status)
  defp status_text(_), do: ""

  defp filter_clause(fields, {key, op}, params) when op in [:is_nil, :not_nil],
    do: filter_clause(fields, {key, op, nil}, params)

  defp filter_clause(fields, {key, op, value}, params) when is_binary(key) and op in @ops do
    case Map.fetch(fields, key) do
      {:ok, field} ->
        type = FieldIndexes.query_type(field)

        if type == "text" and op not in @text_ops,
          do: {:error, {:invalid_operator, key, op}},
          else: compare(key, type, op, value, params)

      :error ->
        {:error, {:unknown_field, key}}
    end
  end

  defp filter_clause(_fields, {key, op, _value}, _params),
    do: {:error, {:invalid_operator, key, op}}

  defp filter_clause(_fields, other, _params), do: {:error, {:invalid_filter, other}}

  defp compare(key, type, op, _value, params) when op in [:is_nil, :not_nil] do
    expr = FieldIndexes.expression("d.data", key, type)
    {:ok, "#{expr} IS #{if op == :is_nil, do: "", else: "NOT "}NULL", params}
  end

  defp compare(key, type, :between, {low, high}, params) do
    with {:ok, low} <- cast(type, low),
         {:ok, high} <- cast(type, high) do
      n = length(params)
      expr = FieldIndexes.expression("d.data", key, type)
      {:ok, "#{expr} BETWEEN $#{n + 1}::#{type} AND $#{n + 2}::#{type}", params ++ [low, high]}
    else
      :error -> {:error, {:invalid_value, key}}
    end
  end

  defp compare(key, type, :in, values, params) when is_list(values) do
    case cast_all(type, values) do
      {:ok, cast} ->
        n = length(params) + 1
        expr = FieldIndexes.expression("d.data", key, type)

        clause =
          if type == "text" do
            "#{expr} = ANY(ARRAY(SELECT left(v, 255) FROM unnest($#{n}::text[]) v)) AND " <>
              "#{FieldIndexes.text_expression("d.data", key)} = ANY($#{n}::text[])"
          else
            "#{expr} = ANY($#{n}::#{type}[])"
          end

        {:ok, clause, params ++ [cast]}

      :error ->
        {:error, {:invalid_value, key}}
    end
  end

  defp compare(key, type, op, value, params) when op in [:eq, :neq, :lt, :lte, :gt, :gte] do
    case cast(type, value) do
      {:ok, cast} ->
        n = length(params) + 1
        expr = FieldIndexes.expression("d.data", key, type)
        sql_op = sql_op(op)

        clause =
          case {type, op} do
            {"text", :eq} ->
              "#{expr} = left($#{n}::text, 255) AND " <>
                "#{FieldIndexes.text_expression("d.data", key)} = $#{n}::text"

            {"text", :neq} ->
              "#{FieldIndexes.text_expression("d.data", key)} <> $#{n}::text"

            _ ->
              "#{expr} #{sql_op} $#{n}::#{type}"
          end

        {:ok, clause, params ++ [cast]}

      :error ->
        {:error, {:invalid_value, key}}
    end
  end

  defp compare(key, _type, op, _value, _params), do: {:error, {:invalid_operator, key, op}}

  defp sql_op(:eq), do: "="
  defp sql_op(:neq), do: "<>"
  defp sql_op(:lt), do: "<"
  defp sql_op(:lte), do: "<="
  defp sql_op(:gt), do: ">"
  defp sql_op(:gte), do: ">="

  defp order_clause(_entity, nil), do: {:ok, "d.position ASC NULLS LAST, d.uuid ASC"}

  defp order_clause(entity, {key, dir}) when dir in [:asc, :desc] do
    case Enum.find(entity.fields_definition || [], &(&1["key"] == key)) do
      nil ->
        {:error, {:unknown_field, key}}

      field ->
        expr = FieldIndexes.expression("d.data", key, FieldIndexes.query_type(field))
        dir = if dir == :asc, do: "ASC", else: "DESC"
        {:ok, "#{expr} #{dir} NULLS LAST, d.position ASC NULLS LAST, d.uuid ASC"}
    end
  end

  defp order_clause(_entity, other), do: {:error, {:invalid_order, other}}

  # ── values ──────────────────────────────────────────────────────────

  defp cast_all(type, values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case cast(type, value) do
        {:ok, v} -> {:cont, {:ok, acc ++ [v]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp cast("numeric", %Decimal{} = d), do: finite(d)
  defp cast("numeric", n) when is_integer(n), do: finite(Decimal.new(n))
  defp cast("numeric", n) when is_float(n), do: {:ok, Decimal.from_float(n)}

  defp cast("numeric", s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {d, ""} -> finite(d)
      _ -> :error
    end
  end

  defp cast("date", %Date{} = d), do: {:ok, d}

  defp cast("date", s) when is_binary(s) do
    case Date.from_iso8601(String.trim(s)) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp cast("text", s) when is_binary(s), do: {:ok, s}
  defp cast("text", v) when is_number(v) or is_atom(v), do: {:ok, to_string(v)}
  defp cast(_type, _value), do: :error

  # NaN compares greater than every number in Postgres (`5 <= 'NaN'` is
  # true), and a value past Postgres' numeric range cannot be sent at all;
  # neither can match a stored value, both are an invalid filter. The
  # bounds are far past what `phoenix_kit_entities_try_numeric` stores.
  @max_digits 1000
  @max_exp 10_000

  @max_coef Integer.pow(10, @max_digits)

  defp finite(%Decimal{coef: coef, exp: exp} = d) when is_integer(coef) do
    if coef < @max_coef and abs(exp) <= @max_exp,
      do: {:ok, d},
      else: :error
  end

  defp finite(_nan_or_inf), do: :error

  # ── loading ─────────────────────────────────────────────────────────

  defp fetch_entity(%Entities{} = entity), do: {:ok, entity}

  defp fetch_entity(ref) when is_binary(ref) do
    entity =
      case Ecto.UUID.cast(ref) do
        {:ok, uuid} -> Entities.get_entity(uuid)
        :error -> Entities.get_entity_by_name(ref)
      end

    if entity, do: {:ok, entity}, else: {:error, :entity_not_found}
  end

  defp fetch_entity(_), do: {:error, :entity_not_found}

  defp load([], _opts), do: []

  defp load(uuids, opts) do
    by_uuid =
      from(d in EntityData, where: d.uuid in ^uuids, preload: [:entity, :creator])
      |> repo().all()
      |> Map.new(&{&1.uuid, &1})

    records = uuids |> Enum.map(&by_uuid[&1]) |> Enum.reject(&is_nil/1)

    case opts[:lang] do
      lang when is_binary(lang) -> EntityData.resolve_languages(records, lang)
      _ -> records
    end
  end
end
