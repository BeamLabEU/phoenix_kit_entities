defmodule PhoenixKitEntities.EntityDataCreatedByTest do
  @moduledoc """
  Regression guard for the public form's `not_null_violation` on
  `created_by_uuid`.

  `phoenix_kit_entity_data.created_by_uuid` is NOT NULL in core's chain, and
  `create/2` auto-fills it "if not provided". The public entity form is
  deliberately unauthenticated, so it passed `created_by_uuid` as an explicit
  nil — which a `Map.has_key?/2` test reads as "provided". The auto-fill was
  skipped and the insert raised Postgrex 23502 out of an unauthenticated
  controller.

  The distinction under test is therefore explicit-nil vs absent, in both key
  forms, because the controller sends string keys and internal callers send
  atoms.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    admin = PhoenixKit.Test.Fixtures.admin_fixture()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "created_by_probe",
          display_name: "Created By Probe",
          display_name_plural: "Created By Probes",
          status: "published",
          fields_definition: [%{"type" => "text", "key" => "title", "label" => "Title"}],
          created_by_uuid: admin.uuid
        },
        actor_uuid: admin.uuid
      )

    {:ok, entity: entity, admin: admin}
  end

  # Which side of the V169 gate this install is on. The behaviour under test
  # differs by design: before V169 the column is NOT NULL and an explicit nil
  # must be auto-filled to avoid a 23502; from V169 on it means "no author" and
  # is stored. Asserting one of those unconditionally makes the suite red on the
  # other core, which is how a suite gets ignored.
  defp anonymous_creator_supported? do
    PhoenixKit.Migrations.Postgres.migrated_version_runtime([]) >= 169
  rescue
    _ -> false
  end

  defp params(entity, extra) do
    Map.merge(
      %{
        "entity_uuid" => entity.uuid,
        "title" => "submission #{System.unique_integer([:positive])}",
        "slug" => "submission-#{System.unique_integer([:positive])}",
        "status" => "published",
        "data" => %{},
        "metadata" => %{"source" => "public_form"}
      },
      extra
    )
  end

  test "an explicit nil creator is honoured or auto-filled, but never raises", ctx do
    assert {:ok, record} =
             EntityData.create(params(ctx.entity, %{"created_by_uuid" => nil}))

    if anonymous_creator_supported?() do
      assert is_nil(record.created_by_uuid)
    else
      assert record.created_by_uuid == ctx.admin.uuid
    end
  end

  test "omitting the creator entirely still auto-fills", ctx do
    assert {:ok, record} = EntityData.create(params(ctx.entity, %{}))
    assert record.created_by_uuid == ctx.admin.uuid
  end

  test "a supplied creator is never overwritten by the auto-fill", ctx do
    other = PhoenixKit.Test.Fixtures.confirmed_user_fixture()

    assert {:ok, record} =
             EntityData.create(params(ctx.entity, %{"created_by_uuid" => other.uuid}))

    assert record.created_by_uuid == other.uuid
  end

  test "an atom-keyed explicit nil takes the same path", ctx do
    assert {:ok, record} =
             EntityData.create(%{
               entity_uuid: ctx.entity.uuid,
               title: "atom keyed",
               slug: "atom-keyed-#{System.unique_integer([:positive])}",
               status: "published",
               created_by_uuid: nil
             })

    if anonymous_creator_supported?() do
      assert is_nil(record.created_by_uuid)
    else
      assert record.created_by_uuid == ctx.admin.uuid
    end
  end

  test "an explicit nil position is auto-filled rather than stored as NULL", ctx do
    assert {:ok, first} = EntityData.create(params(ctx.entity, %{"position" => nil}))
    assert is_integer(first.position)

    assert {:ok, second} = EntityData.create(params(ctx.entity, %{"position" => nil}))
    assert second.position > first.position
  end

  test "an anonymous submission is not filed in the auto-filled creator's audit trail", ctx do
    # The creator column has to hold somebody (it is NOT NULL), but the audit
    # trail records who ACTED — and nobody signed in did. Passing actor_uuid
    # explicitly as nil keeps the log honest; without it the fallback would file
    # the row under the first Owner, reading as though they posted it.
    assert {:ok, record} = EntityData.create(params(ctx.entity, %{}), actor_uuid: nil)
    assert record.created_by_uuid == ctx.admin.uuid

    row = assert_activity_logged("entity_data.created", resource_uuid: record.uuid)
    assert is_nil(row.actor_uuid)
  end

  test "a signed-in submitter is still recorded as the actor", ctx do
    user = PhoenixKit.Test.Fixtures.confirmed_user_fixture()

    assert {:ok, record} =
             EntityData.create(params(ctx.entity, %{"created_by_uuid" => user.uuid}),
               actor_uuid: user.uuid
             )

    assert_activity_logged("entity_data.created",
      resource_uuid: record.uuid,
      actor_uuid: user.uuid
    )
  end

  test "a legacy row with a NULL creator can still be edited", ctx do
    {:ok, record} = EntityData.create(params(ctx.entity, %{}))

    # Reproduce what #706 measured on a live installation: the column is still
    # nullable there (V164 declines to re-impose NOT NULL while NULLs exist) and
    # some rows predate the constraint. The creator check is an INSERT guard —
    # applying it to updates would reject an edit that never touched the field.
    Repo.query!("ALTER TABLE phoenix_kit_entity_data ALTER COLUMN created_by_uuid DROP NOT NULL")

    Repo.query!("UPDATE phoenix_kit_entity_data SET created_by_uuid = NULL WHERE uuid = $1", [
      Ecto.UUID.dump!(record.uuid)
    ])

    legacy = Repo.get!(EntityData, record.uuid)
    assert is_nil(legacy.created_by_uuid)

    assert {:ok, updated} = EntityData.update(legacy, %{"title" => "retitled"})
    assert updated.title == "retitled"
  end

  # Pins the contract rather than the mechanism: today the "does not exist"
  # validation rejects this before the FK is consulted, and the FK declaration
  # is the backstop if that ever changes.
  test "a non-existent entity_uuid is a changeset error, not a raise", ctx do
    assert {:error, %Ecto.Changeset{} = changeset} =
             EntityData.create(%{
               "entity_uuid" => Ecto.UUID.generate(),
               "title" => "orphan",
               "created_by_uuid" => ctx.admin.uuid
             })

    assert Keyword.has_key?(changeset.errors, :entity_uuid)
  end

  test "an entity with an explicit nil position is still ordered", ctx do
    _ = ctx

    assert {:ok, entity} =
             Entities.create_entity(%{
               name: "nil_position_#{System.unique_integer([:positive])}",
               display_name: "Nil Position",
               display_name_plural: "Nil Positions",
               position: nil
             })

    assert is_integer(entity.position)
  end

  test "an entity keeps requiring an author", ctx do
    _ = ctx

    # `phoenix_kit_entities.created_by_uuid` stays NOT NULL — there is no
    # anonymous path for creating an entity — so an explicit nil is reported
    # rather than quietly replaced with an administrator.
    assert {:error, %Ecto.Changeset{} = changeset} =
             Entities.create_entity(%{
               name: "explicit_nil_creator_#{System.unique_integer([:positive])}",
               display_name: "Explicit Nil",
               display_name_plural: "Explicit Nils",
               created_by_uuid: nil
             })

    assert Keyword.has_key?(changeset.errors, :created_by_uuid)
  end
end

defmodule PhoenixKitEntities.EntityDataCreatedByWithoutUsersTest do
  @moduledoc """
  The other half of the creator contract: what happens on an installation with
  no user at all, where the auto-fill has nobody to attribute a submission to.

  A separate module because `setup` applies to every test in a module — the
  sibling test file seeds an admin, and this case is precisely the absence of
  one.
  """
  use PhoenixKitEntities.DataCase, async: false

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  test "a creatorless submission is a changeset error, not a Postgrex raise" do
    # `create/2` documents this case as "a validation error on created_by".
    # Before the fix it was a raw Postgrex 23502 raised out of an
    # unauthenticated controller — a 500 where a 422 belongs. The changeset
    # rejects it before any insert, so no real entity row is needed.
    assert {:error, %Ecto.Changeset{} = changeset} =
             EntityData.create(%{
               "entity_uuid" => Ecto.UUID.generate(),
               "title" => "no creator anywhere",
               "created_by_uuid" => nil
             })

    if PhoenixKit.Migrations.Postgres.migrated_version_runtime([]) >= 169 do
      # From V169 a missing creator is legal, so the made-up entity is what
      # fails — the point being that neither case raises.
      assert Keyword.has_key?(changeset.errors, :entity_uuid)
    else
      assert Keyword.has_key?(changeset.errors, :created_by_uuid)
    end
  end

  test "a userless installation cannot define an entity either" do
    # Pre-existing behaviour of `Entity`'s own `validate_creator_reference/1`,
    # asserted here because it is what makes the userless public-form scenario
    # unreachable in practice: no user means no entity, and no entity means no
    # public form to submit to.
    assert {:error, %Ecto.Changeset{} = changeset} =
             Entities.create_entity(%{
               name: "userless_probe",
               display_name: "Userless Probe",
               display_name_plural: "Userless Probes"
             })

    assert Keyword.has_key?(changeset.errors, :created_by_uuid)
  end
end

defmodule PhoenixKitEntities.EntityDataAnonymousCreatorTest do
  @moduledoc """
  The other side of the V169 gate: once core makes
  `phoenix_kit_entity_data.created_by_uuid` nullable, an explicit
  `created_by_uuid: nil` means "this submission has no author" and is stored as
  NULL instead of being replaced with the first administrator.

  Excluded by default because this module pins core from Hex and V169 is not in
  a release yet — against the published pin the column is NOT NULL and the
  auto-fill is the correct behaviour, which the sibling test file covers.

      PHOENIX_KIT_PATH=../phoenix_kit PGDATABASE=phoenix_kit_entities_v169_test \\
        mix test --include needs_unreleased_core

  Use a SEPARATE database for that run: `ensure_current/2` migrates whatever it
  is pointed at, so running this against the normal test database would move it
  to V169 and flip the default run's expectations. `anonymous_creator_supported?/0`
  also caches in `:persistent_term`, so the two branches cannot be exercised in
  one run either way.

  Delete this file's tag, and the gate it tests, once core's floor is past V169.
  """
  use PhoenixKitEntities.DataCase, async: false

  @moduletag :needs_unreleased_core

  alias PhoenixKitEntities, as: Entities
  alias PhoenixKitEntities.EntityData

  setup do
    admin = PhoenixKit.Test.Fixtures.admin_fixture()

    {:ok, entity} =
      Entities.create_entity(
        %{
          name: "anon_probe",
          display_name: "Anon Probe",
          display_name_plural: "Anon Probes",
          created_by_uuid: admin.uuid
        },
        actor_uuid: admin.uuid
      )

    {:ok, entity: entity, admin: admin}
  end

  test "an explicit nil creator is stored as NULL, not attributed to an admin", ctx do
    assert {:ok, record} =
             EntityData.create(%{
               "entity_uuid" => ctx.entity.uuid,
               "title" => "anonymous submission",
               "created_by_uuid" => nil,
               "metadata" => %{"source" => "public_form"}
             })

    assert is_nil(record.created_by_uuid)
    refute record.created_by_uuid == ctx.admin.uuid
  end

  test "omitting the key still auto-fills, so internal callers are unchanged", ctx do
    assert {:ok, record} =
             EntityData.create(%{
               "entity_uuid" => ctx.entity.uuid,
               "title" => "internal creation"
             })

    assert record.created_by_uuid == ctx.admin.uuid
  end
end

defmodule PhoenixKitEntities.ConstraintDeclarationTest do
  @moduledoc """
  Every constraint the two schemas declare must exist in the database under
  that exact name — Ecto matches by name, and a declaration naming a
  constraint the chain never created can never fire, so the violation raises
  instead of returning the changeset error the caller handles. The
  `unique_constraint(:name)` on entities pointed at Ecto's derived
  `..._name_index` while the real index is `..._name_uidx`.
  """
  use PhoenixKitEntities.DataCase, async: true

  test "declared constraints exist under their declared names" do
    {:ok, %{rows: constraint_rows}} =
      Repo.query(
        """
        SELECT t.relname, c.conname
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = 'public'
        """,
        []
      )

    {:ok, %{rows: index_rows}} =
      Repo.query(
        """
        SELECT tablename, indexname FROM pg_indexes
        WHERE schemaname = 'public' AND indexdef LIKE 'CREATE UNIQUE INDEX%'
        """,
        []
      )

    existing = MapSet.new(constraint_rows ++ index_rows, fn [t, n] -> {t, n} end)

    checked = [
      {PhoenixKitEntities, PhoenixKitEntities.changeset(%PhoenixKitEntities{}, %{})},
      {PhoenixKitEntities.EntityData,
       PhoenixKitEntities.EntityData.changeset(%PhoenixKitEntities.EntityData{}, %{})}
    ]

    missing =
      for {mod, changeset} <- checked,
          table = mod.__schema__(:source),
          # Grouped per field: entity_uuid deliberately declares both the name
          # core creates and Ecto's default (install age decides which exists);
          # the group passes when ANY declared name is real.
          {{field, type}, names} <-
            Enum.group_by(changeset.constraints, &{&1.field, &1.type}, & &1.constraint),
          not Enum.any?(names, &MapSet.member?(existing, {table, &1})),
          do: "#{inspect(mod)}: #{type} on #{table}.#{field} declared as #{inspect(names)}"

    assert missing == [], Enum.join(missing, "\n")
  end
end
