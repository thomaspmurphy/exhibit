defmodule Exhibit.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/thomaspmurphy/exhibit"

  def project do
    [
      app: :exhibit,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Turns a branch of an Elixir project into a short, runnable Livebook that " <>
          "explains the change, with cell outputs filled in headlessly.",
      package: package(),
      docs: docs(),
      escript: escript(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [~r"^test/fixtures/"],
      aliases: aliases()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv skills mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [main: "readme", source_url: @source_url, extras: ["README.md"]]
  end

  defp escript do
    [main_module: Exhibit.CLI, name: "exhibit"]
  end

  # The escript embeds `priv/runner.exs`, so it is regenerated from `lib/`
  # before every build; a test asserts the committed copy is current.
  defp aliases do
    ["escript.build": ["exhibit.build_runner", "escript.build"]]
  end
end
