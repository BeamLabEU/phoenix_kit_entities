defmodule PhoenixKitEntities.MixProject do
  use Mix.Project

  @version "0.2.10"
  @source_url "https://github.com/BeamLabEU/phoenix_kit_entities"

  def project do
    [
      app: :phoenix_kit_entities,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description:
        "Entities module for PhoenixKit — dynamic content types with flexible field schemas",
      package: package(),

      # Dialyzer
      dialyzer: [plt_add_apps: [:phoenix_kit, :mix]],

      # Coverage — exclude test-support modules so the percentage tracks
      # production code, not boilerplate (DataCase, LiveCase, Test.Endpoint,
      # postgres test migration, etc.).
      test_coverage: [
        ignore_modules: [
          ~r/^PhoenixKitEntities\.Test\./,
          PhoenixKitEntities.DataCase,
          PhoenixKitEntities.LiveCase,
          PhoenixKitEntities.ActivityLogAssertions
        ]
      ],

      # Docs
      name: "PhoenixKitEntities",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # test/support/ is compiled only in :test so DataCase and TestRepo
  # don't leak into the published package.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict", "dialyzer"],
      precommit: [
        "compile --force --warnings-as-errors",
        "deps.unlock --check-unused",
        # Scan for retired Hex deps. Run via `cmd` so Hex bootstraps in a fresh
        # process — the hex.* archive tasks aren't resolvable via Mix.Task.run
        # inside an alias.
        "cmd mix hex.audit",
        "quality.ci"
      ]
    ]
  end

  # phoenix_kit deps resolve from Hex by default. For cross-repo work against a
  # local checkout, export <APP>_PATH — e.g. PHOENIX_KIT_PATH=../phoenix_kit or
  # PHOENIX_KIT_AI_PATH=../phoenix_kit_ai. Unset => the published pin, so
  # mix hex.publish is unaffected.
  defp pk_dep(app, requirement, opts \\ []) do
    env_var = String.upcase(Atom.to_string(app)) <> "_PATH"
    path = System.get_env(env_var, "") |> String.trim()

    cond do
      path != "" -> {app, [path: path, override: true] ++ opts}
      opts == [] -> {app, requirement}
      true -> {app, requirement, opts}
    end
  end

  defp deps do
    [
      # PhoenixKit provides the Module behaviour and Settings API.
      # 1.7.214+ required: Scope.can_access_admin_area?/1 (the rename of the
      # now-`@deprecated` Scope.admin?/1) — an older core has no such function,
      # so this is an UndefinedFunctionError at runtime, not a warning.
      pk_dep(:phoenix_kit, "~> 1.7.214"),

      # LiveView is needed for the admin pages.
      {:phoenix_live_view, "~> 1.0"},

      # Optional: add ex_doc for generating documentation
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},

      # Test-only HTML parser used by Phoenix.LiveViewTest under :test.
      {:lazy_html, "~> 0.1", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PhoenixKitEntities",
      source_ref: "v#{@version}",
      extras: ["guides/entities-guide.md"]
    ]
  end
end
