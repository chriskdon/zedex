defmodule Zedex.MixProject do
  use Mix.Project

  def project do
    [
      app: :zedex,
      version: "0.1.0-prerelease",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),

      # Docs
      name: "Zedex",
      source_url: "https://github.com/chriskdon/zedex",
      homepage_url: "https://github.com/chriskdon/zedex",
      docs: [
        # The main page in the docs
        main: "readme",
        extras: [
          "README.md",
          "CHANGELOG.md"
        ],
        formatters: ["html"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :syntax_tools],
      mod: {Zedex.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
