defmodule TimeQueue.MixProject do
  use Mix.Project

  def project do
    [
      app: :time_queue,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: false,
      deps: deps(),
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
      licenses: "MIT"
    ]
  end

  defp deps do
    []
  end
end
