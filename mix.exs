defmodule TimeQueue.MixProject do
  use Mix.Project

  def project do
    [
      app: :time_queue,
      version: "0.2.2",
      elixir: "~> 1.10",
      start_permanent: false,
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
      TimeQueue is a simple functional timer queue (no processes, no messaging, no erlang timers). Not optimized for performance yet.
      """,
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/lud/time_queue"}
    ]
  end

  defp deps do
    [
      # Dev tools
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.3", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "TimeQueue"
    ]
  end
end
