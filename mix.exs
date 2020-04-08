defmodule TimeQueue.MixProject do
  use Mix.Project

  def project do
    [
      app: :time_queue,
      version: "0.1.1",
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
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/lud/time_queue"}
    ]
  end

  defp deps do
    [{:ex_doc, ">= 0.0.0", only: :dev, runtime: false}]
  end
end
