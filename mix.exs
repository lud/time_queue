defmodule TimeQueue.MixProject do
  use Mix.Project

  @source_url "https://github.com/lud/time_queue"

  def project do
    [
      app: :time_queue,
      version: "1.2.3",
      elixir: "~> 1.10",
      start_permanent: false,
      elixirc_paths: elixirc_paths(Mix.env()),
      source_url: @source_url,
      description:
        "TimeQueue is a simple functional timer queue (no processes, no messaging, " <>
          "no erlang timers), serializable and JSON encodable, based on gb_trees.",
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
      licenses: ["MIT"],
      links: %{
        "Github" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp deps do
    [
      # Dev tools
      {:libdev, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:readmix, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.0", optional: true}
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
      before_commit: [
        &readmix/1,
        {:add, "README.md"},
        &gen_changelog/2,
        {:add, "CHANGELOG.md"}
      ]
    ]
  end

  def readmix(vsn) do
    rdmx = Readmix.new(vars: %{app_vsn: vsn})
    :ok = Readmix.update_file(rdmx, "README.md")
  end

  defp gen_changelog(vsn, info) do
    args = ["cliff", "--tag", vsn, "--with-tag-message", info.annotation, "-o", "CHANGELOG.md"]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_, 0} -> IO.puts("Updated CHANGELOG.md with #{vsn}")
      {out, _} -> {:error, "Could not update CHANGELOG.md:\n\n #{out}"}
    end
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
