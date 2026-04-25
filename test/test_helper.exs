# Test helper for PhoenixKitEntities test suite
#
# Level 1: Unit tests (schemas, changesets, pure functions) always run.
# Level 2: Integration tests require PostgreSQL — automatically excluded
#          when the database is unavailable.
#
# To enable integration tests:
#   createdb phoenix_kit_entities_test
#
# Test infrastructure:
# - PhoenixKitEntities.Test.Repo (test/support/test_repo.ex)
# - PhoenixKitEntities.Test.Endpoint + Router + Layouts + Hooks
#   (test/support/test_*.ex)
# - PhoenixKitEntities.LiveCase (test/support/live_case.ex)
# - PhoenixKitEntities.DataCase (test/support/data_case.ex)
# - PhoenixKitEntities.ActivityLogAssertions
#   (test/support/activity_log_assertions.ex)
# - Test migration (test/support/postgres/migrations/) — settings,
#   activities, entities, and entity_data tables

alias PhoenixKitEntities.Test.Repo, as: TestRepo

# Pin URL prefix to "/" via persistent_term so PhoenixKit.Utils.Routes.path/2
# doesn't try to read the unset application env. Tests can override this
# value if they need a non-empty prefix.
:persistent_term.put(PhoenixKit.Config, %{url_prefix: "/"})

# Check if the test database exists before trying to connect
db_config = Application.get_env(:phoenix_kit_entities, TestRepo, [])
db_name = db_config[:database] || "phoenix_kit_entities_test"

db_check =
  case System.cmd("psql", ["-lqt"], stderr_to_stdout: true) do
    {output, 0} ->
      exists =
        output
        |> String.split("\n")
        |> Enum.any?(fn line ->
          line |> String.split("|") |> List.first("") |> String.trim() == db_name
        end)

      if exists, do: :exists, else: :not_found

    _ ->
      :try_connect
  end

repo_available =
  if db_check == :not_found do
    IO.puts("""
    \n  Test database "#{db_name}" not found — integration tests excluded.
       Run: createdb #{db_name}
    """)

    false
  else
    try do
      {:ok, _} = TestRepo.start_link()

      # Run the test migration that creates settings, activities, and the
      # module-owned tables (entities + entity_data). Idempotent via
      # `create_if_not_exists`.
      migration_path = Path.expand("support/postgres/migrations", __DIR__)
      Ecto.Migrator.run(TestRepo, migration_path, :up, all: true, log: false)

      Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)

      # Compile the require_file paths in elixirc_paths(:test) — needed so
      # support modules are loaded before tests reference them.
      Code.require_file("support/data_case.ex", __DIR__)
      Code.require_file("support/live_case.ex", __DIR__)
      Code.require_file("support/activity_log_assertions.ex", __DIR__)

      true
    rescue
      e ->
        IO.puts("""
        \n  Could not connect to test database — integration tests excluded.
           Run: createdb #{db_name}
           Error: #{Exception.message(e)}
        """)

        false
    catch
      :exit, reason ->
        IO.puts("""
        \n  Could not connect to test database — integration tests excluded.
           Run: createdb #{db_name}
           Error: #{inspect(reason)}
        """)

        false
    end
  end

Application.put_env(:phoenix_kit_entities, :test_repo_available, repo_available)

# Start minimal PhoenixKit services needed for tests
{:ok, _pid} = PhoenixKit.PubSub.Manager.start_link([])
{:ok, _pid} = PhoenixKit.ModuleRegistry.start_link([])

# Start the test endpoint so Phoenix.LiveViewTest can render LVs.
# Skipped if the repo isn't available — LV tests need both.
if repo_available do
  {:ok, _pid} = PhoenixKitEntities.Test.Endpoint.start_link()
end

# Exclude integration tests when DB is not available
exclude = if repo_available, do: [], else: [:integration]

ExUnit.start(exclude: exclude)
