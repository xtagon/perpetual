defmodule Perpetual.MixProject do
  use Mix.Project

  def project do
    [
      app: :perpetual,
      version: "0.0.1",
      description: "A simple abstraction around repeatedly iterating state in Elixir.",
      package: package(),
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Docs
      name: "Perpetual",
      source_url: "https://github.com/xtagon/perpetual",
      homepage_url: "https://github.com/xtagon/perpetual",
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "LICENSE",
          "NOTICE"
        ]
      ],

      # Coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.23", only: :dev, runtime: false},
      {:excoveralls, "~> 0.13", only: :test}
    ]
  end

  def package do
    [
      # These are the default files included in the package
      files: ~w(
        .credo.exs
        .formatter.exs
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
        lib
        mix.exs
      ),
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/xtagon/perpetual"
      }
    ]
  end
end
