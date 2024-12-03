defmodule TimeQueue.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/time_queue"

  def project do
    [
      app: :time_queue,
      version: "1.2.0",
      elixir: "~> 1.10",
      start_permanent: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      versioning: versioning(),
      package: package(),
      dialyzer: dialyzer()
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
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      # Dev tools
      {:ex_doc, ">= 0.28.0", only: [:dev], runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:inch_ex, "~> 2.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:jason, "> 0.0.0", only: [:dev, :test], runtime: false},
      {:mix_version, "~> 2.1", only: [:dev, :test], runtime: false}
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

  defp versioning do
    [
      annotate: true,
      before_commit: [
        fn vsn ->
          case System.cmd("git", ["cliff", "--tag", vsn, "-o", "CHANGELOG.md"],
                 stderr_to_stdout: true
               ) do
            {_, 0} -> IO.puts("Updated CHANGELOG.md with #{vsn}")
            {out, _} -> {:error, "Could not update CHANGELOG.md:\n\n #{out}"}
          end
        end,
        add: "CHANGELOG.md"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      flags: [:unmatched_returns, :error_handling, :unknown, :extra_return],
      list_unused_filters: true,
      plt_add_apps: [:ex_unit, :jason],
      plt_local_path: "_build/plts"
    ]
  end

  def cli do
    [
      preferred_envs: [dialyzer: :test]
    ]
  end
end
