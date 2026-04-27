defmodule PhoenixKitEntities.Test.Repo.Migrations.SetupPhoenixKit do
  use Ecto.Migration

  @moduledoc """
  Test-only setup. Mirrors the slice of `phoenix_kit` core +
  `PhoenixKitEntities.Migrations.V1` that the test suite touches:

  - `uuid_generate_v7()` PL/pgSQL function (normally created by core's
    V40 migration)
  - `phoenix_kit_settings` — required for `Settings.get_setting/2`,
    `enabled?/0`, and the Settings-driven URL resolver paths
  - `phoenix_kit_activities` — required for activity log assertions
  - `phoenix_kit_entities` + `phoenix_kit_entity_data` — the module's
    own tables, kept in sync with `PhoenixKitEntities.Migrations.V1`

  Match `phoenix_kit_settings` and `phoenix_kit_activities` columns
  with the real schema so reads/writes don't poison the sandbox
  transaction with column-mismatch errors.
  """

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")
    execute("CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\"")

    execute("""
    CREATE OR REPLACE FUNCTION uuid_generate_v7()
    RETURNS uuid AS $$
    DECLARE
      unix_ts_ms bytea;
      uuid_bytes bytea;
    BEGIN
      unix_ts_ms := substring(int8send(floor(extract(epoch FROM clock_timestamp()) * 1000)::bigint) FROM 3);
      uuid_bytes := unix_ts_ms || gen_random_bytes(10);
      uuid_bytes := set_byte(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112);
      uuid_bytes := set_byte(uuid_bytes, 8, (get_byte(uuid_bytes, 8) & 63) | 128);
      RETURN encode(uuid_bytes, 'hex')::uuid;
    END
    $$ LANGUAGE plpgsql VOLATILE;
    """)

    create_if_not_exists table(:phoenix_kit_settings, primary_key: false) do
      add(:uuid, :uuid, primary_key: true, default: fragment("uuid_generate_v7()"))
      add(:key, :string, null: false, size: 255)
      add(:value, :string)
      add(:value_json, :map)
      add(:module, :string, size: 50)
      add(:date_added, :utc_datetime_usec, null: false, default: fragment("NOW()"))
      add(:date_updated, :utc_datetime_usec, null: false, default: fragment("NOW()"))
    end

    create_if_not_exists(unique_index(:phoenix_kit_settings, [:key]))

    # Users table — minimal subset of phoenix_kit core's V1 user schema.
    # Required because `Entities.get_entity/2` preloads the `:creator`
    # association, which issues a `SELECT ... FROM phoenix_kit_users`
    # even when no users exist. Without this table the preload crashes
    # with `relation "phoenix_kit_users" does not exist`.
    create_if_not_exists table(:phoenix_kit_users, primary_key: false) do
      add(:uuid, :uuid, primary_key: true, default: fragment("uuid_generate_v7()"))
      add(:email, :string)
      add(:username, :string)
      add(:hashed_password, :string)
      add(:first_name, :string)
      add(:last_name, :string)
      add(:is_active, :boolean, default: true)
      add(:confirmed_at, :utc_datetime)
      add(:user_timezone, :string)
      add(:registration_ip, :string)
      add(:registration_country, :string)
      add(:registration_region, :string)
      add(:registration_city, :string)
      add(:custom_fields, :map, default: %{})
      add(:account_type, :string, default: "personal")
      add(:organization_name, :string)
      add(:organization_uuid, :uuid)
      add(:inserted_at, :utc_datetime, null: false, default: fragment("NOW()"))
      add(:updated_at, :utc_datetime, null: false, default: fragment("NOW()"))
    end

    create_if_not_exists table(:phoenix_kit_activities, primary_key: false) do
      add(:uuid, :binary_id, primary_key: true)
      add(:action, :string, null: false, size: 100)
      add(:module, :string, size: 50)
      add(:mode, :string, size: 20)
      add(:actor_uuid, :binary_id)
      add(:resource_type, :string, size: 50)
      add(:resource_uuid, :binary_id)
      add(:target_uuid, :binary_id)
      add(:metadata, :map, default: %{})
      add(:inserted_at, :utc_datetime, null: false, default: fragment("now()"))
    end

    create_if_not_exists(index(:phoenix_kit_activities, [:module]))
    create_if_not_exists(index(:phoenix_kit_activities, [:action]))
    create_if_not_exists(index(:phoenix_kit_activities, [:actor_uuid]))
    create_if_not_exists(index(:phoenix_kit_activities, [:inserted_at]))

    # ── Module-owned tables (kept in sync with Migrations.V1) ──────

    create_if_not_exists table(:phoenix_kit_entities, primary_key: false) do
      add(:uuid, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v7()"))
      add(:name, :string, null: false)
      add(:display_name, :string, null: false)
      add(:display_name_plural, :string)
      add(:description, :text)
      add(:icon, :string)
      add(:status, :string, null: false, default: "draft")
      add(:fields_definition, :map, null: false, default: "[]")
      add(:settings, :map, null: true)
      add(:created_by_uuid, :uuid)
      add(:date_created, :utc_datetime_usec, null: false, default: fragment("NOW()"))
      add(:date_updated, :utc_datetime_usec, null: false, default: fragment("NOW()"))
    end

    create_if_not_exists(unique_index(:phoenix_kit_entities, [:name]))
    create_if_not_exists(index(:phoenix_kit_entities, [:created_by_uuid]))
    create_if_not_exists(index(:phoenix_kit_entities, [:status]))

    create_if_not_exists table(:phoenix_kit_entity_data, primary_key: false) do
      add(:uuid, :uuid, primary_key: true, null: false, default: fragment("uuid_generate_v7()"))
      add(:entity_uuid, :uuid, null: false)
      add(:title, :string, null: false)
      add(:slug, :string)
      add(:status, :string, null: false, default: "draft")
      add(:position, :integer)
      add(:data, :map, null: false, default: "{}")
      add(:metadata, :map, null: true)
      add(:created_by_uuid, :uuid)
      add(:date_created, :utc_datetime_usec, null: false, default: fragment("NOW()"))
      add(:date_updated, :utc_datetime_usec, null: false, default: fragment("NOW()"))
    end

    create_if_not_exists(index(:phoenix_kit_entity_data, [:entity_uuid]))
    create_if_not_exists(index(:phoenix_kit_entity_data, [:slug]))
    create_if_not_exists(index(:phoenix_kit_entity_data, [:status]))
    create_if_not_exists(index(:phoenix_kit_entity_data, [:created_by_uuid]))
    create_if_not_exists(index(:phoenix_kit_entity_data, [:title]))
    create_if_not_exists(index(:phoenix_kit_entity_data, [:entity_uuid, :position]))

    # FK with cascade so deleting an entity wipes its data records.
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'phoenix_kit_entity_data_entity_uuid_fkey'
      ) THEN
        ALTER TABLE phoenix_kit_entity_data
          ADD CONSTRAINT phoenix_kit_entity_data_entity_uuid_fkey
          FOREIGN KEY (entity_uuid)
          REFERENCES phoenix_kit_entities(uuid)
          ON DELETE CASCADE;
      END IF;
    END
    $$;
    """)
  end

  def down do
    drop_if_exists(table(:phoenix_kit_entity_data))
    drop_if_exists(table(:phoenix_kit_entities))
    drop_if_exists(table(:phoenix_kit_activities))
    drop_if_exists(table(:phoenix_kit_settings))
  end
end
