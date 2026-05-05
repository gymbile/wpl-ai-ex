defmodule WplAi.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/gymbile/wpl-ai-ex"

  def project do
    [
      app: :wpl_ai,
      version: @version,
      elixir: "~> 1.15",
      description: description(),
      package: package(),
      deps: deps(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://wpl.dev",
      name: "WPL-AI",
      start_permanent: Mix.env() == :prod
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp description do
    "WPL-AI compiler: parses WPL-AI DSL into WPL JSON. Reference Elixir implementation."
  end

  defp package do
    [
      maintainers: ["Gymbile"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Schema" => "https://github.com/gymbile/wpl",
        "Spec" => "https://wpl.dev"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "WplAi",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
