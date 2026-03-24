defmodule PhoenixKitEntities.Migrations.V1 do
  @moduledoc """
  Consolidated migration for the PhoenixKit Entities module.

  Creates the `phoenix_kit_entities` and `phoenix_kit_entity_data` tables
  with their final schema (UUIDv7 primary keys, timestamptz columns, all indexes).

  All operations use IF NOT EXISTS / idempotent guards so this migration is safe
  to run even if the tables already exist from PhoenixKit core migrations.

  ## Tables

  ### phoenix_kit_entities
  Entity definitions (content type blueprints) with JSONB field schemas.

  ### phoenix_kit_entity_data
  Entity data records (instances) with JSONB field values.

  ## Settings Seeds
  Inserts default entities-related settings if not already present.
  """

  use Ecto.Migration

  def up(%{prefix: prefix} = _opts) do
    # Ensure UUIDv7 generation function exists
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

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

    # ── phoenix_kit_entities ──────────────────────────────────────────────

    create_if_not_exists table(:phoenix_kit_entities, primary_key: false, prefix: prefix) do
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

    create_if_not_exists(
      unique_index(:phoenix_kit_entities, [:name],
        name: :phoenix_kit_entities_name_uidx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entities, [:created_by_uuid],
        name: :phoenix_kit_entities_created_by_uuid_idx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entities, [:status],
        name: :phoenix_kit_entities_status_idx,
        prefix: prefix
      )
    )

    # ── phoenix_kit_entity_data ───────────────────────────────────────────

    create_if_not_exists table(:phoenix_kit_entity_data, primary_key: false, prefix: prefix) do
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

    create_if_not_exists(
      index(:phoenix_kit_entity_data, [:entity_uuid],
        name: :phoenix_kit_entity_data_entity_uuid_idx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entity_data, [:slug],
        name: :phoenix_kit_entity_data_slug_idx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entity_data, [:status],
        name: :phoenix_kit_entity_data_status_idx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entity_data, [:created_by_uuid],
        name: :phoenix_kit_entity_data_created_by_uuid_idx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entity_data, [:title],
        name: :phoenix_kit_entity_data_title_idx,
        prefix: prefix
      )
    )

    create_if_not_exists(
      index(:phoenix_kit_entity_data, [:entity_uuid, :position],
        name: :phoenix_kit_entity_data_entity_position_idx,
        prefix: prefix
      )
    )

    # ── Foreign key (entity_data → entities) ──────────────────────────────

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'phoenix_kit_entity_data_entity_uuid_fkey'
        AND conrelid = '#{prefix_table("phoenix_kit_entity_data", prefix)}'::regclass
      ) THEN
        ALTER TABLE #{prefix_table("phoenix_kit_entity_data", prefix)}
        ADD CONSTRAINT phoenix_kit_entity_data_entity_uuid_fkey
        FOREIGN KEY (entity_uuid)
        REFERENCES #{prefix_table("phoenix_kit_entities", prefix)}(uuid)
        ON DELETE CASCADE;
      END IF;
    END $$;
    """)

    # ── Settings seeds ────────────────────────────────────────────────────

    if table_exists?(:phoenix_kit_settings, prefix) do
      execute("""
      INSERT INTO #{prefix_table("phoenix_kit_settings", prefix)} (key, value, module, date_added, date_updated)
      VALUES
        ('entities_enabled', 'false', 'entities', NOW(), NOW()),
        ('entities_max_per_user', '100', 'entities', NOW(), NOW()),
        ('entities_allow_relations', 'true', 'entities', NOW(), NOW()),
        ('entities_file_upload', 'false', 'entities', NOW(), NOW())
      ON CONFLICT (key) DO NOTHING
      """)
    end

    # ── Column comments ───────────────────────────────────────────────────

    execute("""
    COMMENT ON COLUMN #{prefix_table("phoenix_kit_entities", prefix)}.fields_definition IS
    'JSONB array of field definitions. Each field has type, key, label, validation rules.'
    """)

    execute("""
    COMMENT ON COLUMN #{prefix_table("phoenix_kit_entities", prefix)}.settings IS
    'JSONB storage for entity-specific settings (sort_mode, mirror toggles, public_form config, etc.).'
    """)

    execute("""
    COMMENT ON COLUMN #{prefix_table("phoenix_kit_entity_data", prefix)}.data IS
    'JSONB storage for all field values based on entity definition. Structure matches fields_definition.'
    """)

    execute("""
    COMMENT ON COLUMN #{prefix_table("phoenix_kit_entity_data", prefix)}.metadata IS
    'JSONB storage for additional metadata (tags, categories, search keywords, etc.).'
    """)

    execute("""
    COMMENT ON COLUMN #{prefix_table("phoenix_kit_entity_data", prefix)}.position IS
    'Integer position for manual ordering per entity. Null when entity uses auto sort mode.'
    """)
  end

  def down(%{prefix: prefix} = _opts) do
    # Drop foreign key constraint if it exists
    execute("""
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'phoenix_kit_entity_data_entity_uuid_fkey'
        AND conrelid = '#{prefix_table("phoenix_kit_entity_data", prefix)}'::regclass
      ) THEN
        ALTER TABLE #{prefix_table("phoenix_kit_entity_data", prefix)}
        DROP CONSTRAINT phoenix_kit_entity_data_entity_uuid_fkey;
      END IF;
    END $$;
    """)

    drop_if_exists(
      index(:phoenix_kit_entity_data, [:entity_uuid, :position],
        name: :phoenix_kit_entity_data_entity_position_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entity_data, [:title],
        name: :phoenix_kit_entity_data_title_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entity_data, [:created_by_uuid],
        name: :phoenix_kit_entity_data_created_by_uuid_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entity_data, [:status],
        name: :phoenix_kit_entity_data_status_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entity_data, [:slug],
        name: :phoenix_kit_entity_data_slug_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entity_data, [:entity_uuid],
        name: :phoenix_kit_entity_data_entity_uuid_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entities, [:status],
        name: :phoenix_kit_entities_status_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entities, [:created_by_uuid],
        name: :phoenix_kit_entities_created_by_uuid_idx,
        prefix: prefix
      )
    )

    drop_if_exists(
      index(:phoenix_kit_entities, [:name],
        name: :phoenix_kit_entities_name_uidx,
        prefix: prefix
      )
    )

    drop_if_exists(table(:phoenix_kit_entity_data, prefix: prefix))
    drop_if_exists(table(:phoenix_kit_entities, prefix: prefix))

    if table_exists?(:phoenix_kit_settings, prefix) do
      execute("""
      DELETE FROM #{prefix_table("phoenix_kit_settings", prefix)}
      WHERE key IN ('entities_enabled', 'entities_max_per_user', 'entities_allow_relations', 'entities_file_upload')
      """)
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  defp table_exists?(table_name, prefix) do
    schema = prefix || "public"

    query = """
    SELECT EXISTS (
      SELECT FROM information_schema.tables
      WHERE table_schema = '#{schema}'
      AND table_name = '#{table_name}'
    )
    """

    %{rows: [[exists]]} = repo().query!(query)
    exists
  end

  defp prefix_table(table_name, nil), do: table_name
  defp prefix_table(table_name, prefix), do: "#{prefix}.#{table_name}"
end
