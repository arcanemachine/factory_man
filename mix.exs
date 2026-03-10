defmodule FactoryMan.MixProject do
  use Mix.Project

  @project_name "Factory Man"
  @source_url "https://github.com/arcanemachine/factory_man"
  @version "0.3.0"

  def project do
    [
      app: :factory_man,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),

      # Hex
      description:
        "Test data factories with automatic struct building, database insertion, and customizable hooks",
      package: package(),

      # Docs
      name: @project_name,
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      name: :factory_man,
      files: ~w(.formatter.exs CHANGELOG.md LICENSE.md README.md mix.exs lib),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Nicholas Moen"]
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},

      # Required when using `insert_*` functions
      {:ecto_sql, "~> 3.0", optional: true},

      # Required if using PostgreSQL
      {:postgrex, ">= 0.0.0", optional: true}
    ]
  end

  defp docs do
    [
      main: @project_name,
      extras: [
        "README.md": [title: "README"],
        "CHANGELOG.md": [title: "Changelog"]
      ],
      formatters: ["html"],
      main: "readme"
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
