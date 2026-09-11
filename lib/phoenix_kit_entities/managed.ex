defmodule PhoenixKitEntities.Managed do
  @moduledoc """
  Support for MANAGED entity blueprints — blueprints owned by another
  module (e.g. the catalogue's attribute sets), created and administered
  exclusively through that module's own UI on top of the entities API.

  A managed blueprint carries in its `settings`:

      "managed_by"  => "catalogue"          # owning module key
      "locked_keys" => ["kind", ...]        # settings["<owner>"] keys the
                                            # generic write path must not touch

  ## The two guarantees

  1. **Hidden from the generic admin** — `managed?/1` lets listings
     exclude these blueprints (`PhoenixKitEntities.list_entities/1`
     accepts `include_managed: false`); the owning module renders its
     own management UI.
  2. **Write-path protection** — `validate_mutation/2` and
     `validate_delete/1` are called by the entities write path (not just
     the UI): mutations from anywhere but the owning module cannot
     rename the blueprint's slug, change its status, or touch locked
     settings keys; deletion requires the owner's confirmation callback
     to approve (e.g. the catalogue refuses while item attachments
     exist). UI guards without a write interceptor are theater.
     One write path is deliberately outside the interception:
     `reorder_entities/2` bulk-updates `position` via `update_all`, and
     `position` is not part of any owner contract. The same theater
     risk applies one level down: `validate_data_mutation/4` protects a
     DATA RECORD's `slug` the same way, since the owner's own tables key
     relations on it (e.g. the catalogue's `selected_value_slugs`) — every
     other data-record field is unguarded and goes through the ordinary
     `EntityData` write path untouched.

  Owners bypass the guard by passing `on_behalf_of: "<owner>"` in opts —
  the guard is against *accidental* generic-admin edits, not a security
  boundary (all callers are admin code).

  ## Delete approval

  Owners register a delete-approval callback at runtime:

      PhoenixKitEntities.Managed.register_delete_guard(
        "catalogue",
        &MyApp.Catalogue.deletion_guard/1
      )

  where `deletion_guard/1` returns `:ok` or `{:error, reason}` (e.g.
  `{:error, :set_in_use}` while item attachments exist). The callback
  MUST be an external capture (`&Mod.fun/1`), never an anonymous fun: a
  local capture in `:persistent_term` goes stale when the registering
  module is purged (code reload / hot upgrade), raises on call, and
  every delete then fails closed with `{:error, :delete_guard_error}`.

  Registration is process-independent (persistent_term), set up in the
  owning module's application start. A managed blueprint with no
  registered guard refuses deletion outright — fail closed.
  """

  @pt_key {__MODULE__, :delete_guards}

  @doc "True when the entity is managed by another module."
  @spec managed?(struct() | map()) :: boolean()
  def managed?(%{settings: settings}) when is_map(settings),
    do: is_binary(settings["managed_by"])

  def managed?(_), do: false

  @doc "The owning module key, or nil."
  @spec owner(struct() | map()) :: String.t() | nil
  def owner(%{settings: settings}) when is_map(settings), do: settings["managed_by"]
  def owner(_), do: nil

  @doc """
  Validates an update to `entity` with `attrs`. Returns `:ok` or
  `{:error, reason}`. Owner-originated calls (`on_behalf_of` matching
  the owner) pass unconditionally.
  """
  @spec validate_mutation(struct(), map(), keyword()) ::
          :ok | {:error, :managed_blueprint | :locked_key}
  def validate_mutation(entity, attrs, opts \\ []) do
    cond do
      # Acquisition first: an update that ADDS markers to a previously
      # unmanaged blueprint is the create-then-update masquerade — the
      # `not managed?` short-circuit below reads the OLD settings and
      # would wave it through (panel finding, 2026-08-19 review).
      acquires_markers?(entity, attrs, opts) -> {:error, :managed_blueprint}
      not managed?(entity) -> :ok
      Keyword.get(opts, :on_behalf_of) == owner(entity) -> :ok
      renames_identity?(entity, attrs) -> {:error, :managed_blueprint}
      tampers_with_markers?(entity, attrs) -> {:error, :managed_blueprint}
      touches_locked_keys?(entity, attrs) -> {:error, :locked_key}
      true -> :ok
    end
  end

  @doc """
  Validates CREATING an entity with `attrs`: a blueprint claiming a
  `managed_by` owner can only be provisioned by that owner
  (`on_behalf_of` matching). Without this, any generic caller could
  create a blueprint that masquerades as module-owned — hidden from
  the generic admin yet picked up by the owning module's listings
  (panel finding, 2026-08-18 review).
  """
  @spec validate_creation(map(), keyword()) :: :ok | {:error, :managed_blueprint}
  def validate_creation(attrs, opts \\ []) do
    case claimed_owner(attrs) do
      nil ->
        :ok

      claimed when is_binary(claimed) ->
        if Keyword.get(opts, :on_behalf_of) == claimed,
          do: :ok,
          else: {:error, :managed_blueprint}
    end
  end

  @doc """
  Validates an update to a DATA RECORD belonging to `owning_entity` — the
  blueprint the record's `entity_uuid` points at. A managed blueprint's
  owner keys its own relations on a value record's `slug` (e.g. the
  catalogue's `selected_value_slugs`), so a generic caller changing it
  would silently break that relation — the write path refuses it here
  rather than trusting the UI guard alone (see moduledoc). Owner-originated
  calls (`on_behalf_of` matching the owner) pass unconditionally — the
  owner may repoint its own relation. `data_record` supplies the slug's
  PRIOR value: resubmitting a form with the field disabled still posts the
  unchanged slug back (so validation and this guard both see a whole
  payload), and that must not read as a rename.

  Only the record's `slug` is protected — `title`, `status`, `data`, etc.
  go through unguarded, same as for an unmanaged blueprint's records.
  """
  @spec validate_data_mutation(struct() | nil, struct(), map(), keyword()) ::
          :ok | {:error, :locked_key}
  def validate_data_mutation(owning_entity, data_record, attrs, opts \\ []) do
    cond do
      not managed?(owning_entity) -> :ok
      Keyword.get(opts, :on_behalf_of) == owner(owning_entity) -> :ok
      renames_data_slug?(data_record, attrs) -> {:error, :locked_key}
      true -> :ok
    end
  end

  @doc """
  Validates deleting `entity`. Owner-originated calls consult nothing;
  generic calls are refused; the owner's registered guard arbitrates
  owner-side deletes.
  """
  @spec validate_delete(struct(), keyword()) :: :ok | {:error, term()}
  def validate_delete(entity, opts \\ []) do
    cond do
      not managed?(entity) ->
        :ok

      Keyword.get(opts, :on_behalf_of) != owner(entity) ->
        {:error, :managed_blueprint}

      true ->
        case delete_guard(owner(entity)) do
          nil -> {:error, :no_delete_guard}
          fun -> run_delete_guard(fun, entity)
        end
    end
  end

  # A guard that raises must FAIL CLOSED, not propagate: the classic
  # cause is a stale local-fun capture in :persistent_term after the
  # registering module was purged (code reload / hot upgrade) — owners
  # must register EXTERNAL captures (`&Mod.fun/1`), but a blueprint
  # delete must never crash the caller either way.
  defp run_delete_guard(fun, entity) do
    case fun.(entity) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_guard_result, other}}
    end
  rescue
    _ -> {:error, :delete_guard_error}
  catch
    # A guard whose DB call exits (e.g. connection owner death) must
    # fail closed the same way a raise does.
    :exit, _ -> {:error, :delete_guard_error}
  end

  @doc "Registers (replaces) the owner's delete-approval callback."
  @spec register_delete_guard(String.t(), (struct() -> :ok | {:error, term()})) :: :ok
  def register_delete_guard(owner, fun) when is_binary(owner) and is_function(fun, 1) do
    guards = :persistent_term.get(@pt_key, %{})
    :persistent_term.put(@pt_key, Map.put(guards, owner, fun))
    :ok
  end

  defp delete_guard(owner), do: :persistent_term.get(@pt_key, %{}) |> Map.get(owner)

  # The owner a settings payload claims via "managed_by", or nil. Ecto's
  # :map type stores whatever key kind it is given and the JSONB encoder
  # writes atom keys out as strings — so an atom-keyed
  # %{managed_by: "catalogue"} would persist as a managed blueprint while
  # a string-only lookup here reads nil and fails OPEN. Check both key
  # forms (panel finding, 2026-08-19 review).
  defp claimed_owner(attrs) do
    settings = attrs[:settings] || attrs["settings"]

    if is_map(settings) do
      case Map.get(settings, "managed_by") || Map.get(settings, :managed_by) do
        claimed when is_binary(claimed) -> claimed
        _ -> nil
      end
    else
      nil
    end
  end

  # True when an update to an UNMANAGED blueprint would stamp a
  # "managed_by" claim the caller isn't entitled to.
  defp acquires_markers?(entity, attrs, opts) do
    not managed?(entity) and
      case claimed_owner(attrs) do
        nil -> false
        claimed -> Keyword.get(opts, :on_behalf_of) != claimed
      end
  end

  # Identity/status: the slug (`name`) and `status` are part of the
  # owner's contract — other modules reference the blueprint by them.
  defp renames_identity?(entity, attrs) do
    new_name = attrs[:name] || attrs["name"]
    new_status = attrs[:status] || attrs["status"]

    (is_binary(new_name) and new_name != entity.name) or
      (is_binary(new_status) and new_status != entity.status)
  end

  @doc """
  True when `attrs` supplies a `:slug` (or `"slug"`) that differs from
  `data_record.slug` — the relation key a managed blueprint's owner keys
  on (e.g. catalogue's `selected_value_slugs`), same rationale as
  `renames_identity?/2` above, one level down at the data-record layer.

  Presence, not truthiness, decides whether `attrs` even speaks to the
  slug: `Map.fetch/2` (not `attrs[:slug] || attrs["slug"]`), so an
  explicit `slug: nil` reads as a change instead of silently passing as
  "not binary, therefore untouched" and erasing the slug — closing that
  off for any caller that ever builds `attrs` from a source where the
  key can be present-but-nil (`mirror/importer.ex`'s own record-matching
  guard happens to keep the key aligned with the existing slug today,
  but this function doesn't get to assume that of every caller). A key
  simply ABSENT from `attrs` is still not a rename: an ordinary
  title/data save never mentions `:slug` at all.

  `""` and `nil` are the same "no slug" on both sides of the compare:
  the disabled field's hidden mirror posts back `""` when the DATABASE
  value is already `nil` (a record created before the UI stopped
  locking the field on `/data/new`, back-filled or otherwise) — Ecto's
  own `cast/4` would fold that `""` to `nil` too, so failing to close
  here made that resubmit read as a rename of a title-only save.

  Public so `EntityData.update/3` can call it directly, ahead of
  `validate_data_mutation/4`: when this returns `false`, that function
  would return `:ok` no matter what the owning entity turns out to be,
  so there is no reason to pay for looking it up first.
  """
  @spec renames_data_slug?(struct(), map()) :: boolean()
  def renames_data_slug?(data_record, attrs) do
    case fetch_slug(attrs) do
      :error -> false
      {:ok, new_slug} -> normalize_slug(new_slug) != normalize_slug(data_record.slug)
    end
  end

  defp fetch_slug(attrs) do
    case Map.fetch(attrs, :slug) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attrs, "slug")
    end
  end

  defp normalize_slug(""), do: nil
  defp normalize_slug(slug), do: slug

  # The marker keys ARE the protection — a generic settings write that
  # rewrites or drops "managed_by"/"locked_keys" would un-manage the
  # blueprint (or unlock everything) and then walk straight past every
  # other guard (panel finding, 2026-08-18 review). Only settings-bearing
  # updates are checked: an update without :settings can't touch them.
  defp tampers_with_markers?(entity, attrs) do
    new_settings = attrs[:settings] || attrs["settings"]

    if is_map(new_settings) do
      old_settings = entity.settings || %{}

      new_settings["managed_by"] != old_settings["managed_by"] or
        new_settings["locked_keys"] != old_settings["locked_keys"]
    else
      false
    end
  end

  # Locked keys live under settings["<owner>"] — reject any update whose
  # settings change them. Adding NEW keys (or fields_definition changes)
  # stays allowed: extra value fields are the whole point.
  defp touches_locked_keys?(entity, attrs) do
    new_settings = attrs[:settings] || attrs["settings"]

    if is_map(new_settings) do
      owner_key = owner(entity)
      locked = List.wrap((entity.settings || %{})["locked_keys"])
      old_owner_settings = (entity.settings || %{})[owner_key] || %{}
      new_owner_settings = new_settings[owner_key] || %{}

      Enum.any?(locked, fn key ->
        Map.get(new_owner_settings, key) != Map.get(old_owner_settings, key)
      end)
    else
      false
    end
  end
end
