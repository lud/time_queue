defmodule TimeQueue.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/time_queue"

  def project do
    [
      app: :time_queue,
      version: "0.9.6",
      elixir: "~> 1.10",
      start_permanent: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: []
    ]
  end

  defp package() do
    [
      description: """
      TimeQueue is a simple functional timer queue (no processes, no messaging,
      no erlang timers), serializable, based on a single list of maps.
      """,
      licenses: ["MIT"],
      links: %{
        "Github" => @source_url,
        "CHANGELOG" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      # Dev tools
      {:ex_doc, ">= 0.28.0", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:jason, "> 0.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "TimeQueue",
      source_url: @source_url,
      extras: [
        "README.md"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
