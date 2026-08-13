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

  test "an explicit nil creator is auto-filled, not raised on", ctx do
    assert {:ok, record} =
             EntityData.create(params(ctx.entity, %{"created_by_uuid" => nil}))

    assert record.created_by_uuid == ctx.admin.uuid
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

  test "an atom-keyed explicit nil is auto-filled too", ctx do
    assert {:ok, record} =
             EntityData.create(%{
               entity_uuid: ctx.entity.uuid,
               title: "atom keyed",
               slug: "atom-keyed-#{System.unique_integer([:positive])}",
               status: "published",
               created_by_uuid: nil
             })

    assert record.created_by_uuid == ctx.admin.uuid
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

  test "entities themselves take the same treatment", ctx do
    assert {:ok, entity} =
             Entities.create_entity(%{
               name: "explicit_nil_creator_#{System.unique_integer([:positive])}",
               display_name: "Explicit Nil",
               display_name_plural: "Explicit Nils",
               created_by_uuid: nil
             })

    assert entity.created_by_uuid == ctx.admin.uuid
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

    assert Keyword.has_key?(changeset.errors, :created_by_uuid)
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
