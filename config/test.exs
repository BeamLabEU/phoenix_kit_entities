import Config

# Test database configuration
# Integration tests need a real PostgreSQL database. Create it with:
#   createdb phoenix_kit_entities_test
config :phoenix_kit_entities, ecto_repos: [PhoenixKitEntities.Test.Repo]

config :phoenix_kit_entities, PhoenixKitEntities.Test.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "phoenix_kit_entities_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Wire repo for PhoenixKit.RepoHelper — without this, all DB calls crash.
config :phoenix_kit, repo: PhoenixKitEntities.Test.Repo

# Test endpoint config — minimal but sufficient for Phoenix.LiveViewTest.
# Real apps load their full endpoint config from runtime.exs; we just
# need enough for `live/2` to drive the LiveView.
config :phoenix_kit_entities, PhoenixKitEntities.Test.Endpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  render_errors: [
    formats: [html: PhoenixKitEntities.Test.Layouts],
    layout: false
  ],
  pubsub_server: PhoenixKit.PubSub,
  live_view: [signing_salt: "entities-test-salt"],
  server: false

config :logger, level: :warning
