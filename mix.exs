defmodule AshClickhouse.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_clickhouse,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      name: "AshClickhouse",
      docs: docs(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  if Mix.env() == :test do
    def application() do
      [
        mod: {AshClickhouse.TestApp, []}
      ]
    end
  end

  defp docs do
    [
      main: "AshClickhouse",
      extras: ["README.md"],
      groups_for_modules: [
        Types: ~r/^AshClickhouse\.Type\./
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:ecto_ch, "~> 0.8"},
      {:ecto, "~> 3.13"},
      {:jason, "~> 1.0"},
      {:ash, ash_version("~> 3.5")},
      {:ash_sql, ash_sql_version("~> 0.2")},
      {:excoveralls, "~> 0.18", only: :test},
      {:machete, "~> 0.3.11", only: :test},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ex_doc, "~> 0.38", only: [:dev], runtime: false}
      # {:git_ops, "~> 2.5", only: [:dev, :test]},
      # {:ex_check, "~> 0.14", only: [:dev, :test]},
      # {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      # {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      # {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      # {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash", override: true]

      "main" ->
        [git: "https://github.com/ash-project/ash.git", override: true]

      version when is_binary(version) ->
        "~> #{version}"

      version ->
        version
    end
  end

  defp ash_sql_version(default_version) do
    case System.get_env("ASH_SQL_VERSION") do
      nil ->
        default_version

      "local" ->
        [path: "../ash_sql", override: true]

      "main" ->
        [git: "https://github.com/ash-project/ash_sql.git"]

      version when is_binary(version) ->
        "~> #{version}"

      version ->
        version
    end
  end

  defp aliases do
    [
      test: ["ecto.create --quiet", "ecto.migrate", "test"],
      "ecto.reset": ["ecto.drop", "ecto.create --quiet", "ecto.migrate"]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end
end
