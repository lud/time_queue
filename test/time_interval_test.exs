defmodule TimeQueue.TimeIntervalTest do
  alias TimeQueue.TimeInterval
  import Kernel, except: [to_string: 1]
  import TimeQueue.TimeInterval
  use ExUnit.Case, async: true

  doctest TimeQueue.TimeInterval

  test "parsing the intervals" do
    assert 0 == to_ms!("0s")
    assert 0 == to_ms!("0m")
    assert 0 == to_ms!("0h")
    assert 0 == to_ms!("0d")

    # can get bigger than the unit
    assert 100_000 * 1000 == to_ms!("100000s")

    assert 1000 == to_ms!("1s")
    assert 1000 * 60 == to_ms!("1m")
    assert 1000 * 60 * 60 == to_ms!("1h")
    assert 1000 * 60 * 60 * 24 == to_ms!("1d")

    assert 1000 +
             1000 * 60 +
             1000 * 60 * 60 +
             1000 * 60 * 60 * 24 ==
             to_ms!("1d1h1m1s")

    # the order does not count

    assert to_ms!("1d1h1m1s") == to_ms!("1s1m1h1d")

    # duplicate units are cumulative
    assert to_ms!("2d") == to_ms!("1d1d")
    assert to_ms!("2d2h") == to_ms!("1d1d1h1h")
    assert to_ms!("2d2h") == to_ms!("1d1h1d1h")

    # parsing a negative interval
    assert -1 * to_ms!("1d1h1m1s") == to_ms!("-1d1h1m1s")
  end

  test "interval to string" do
    assert "1d1h1m1s" == "1s1m1h1d" |> to_ms!() |> to_string()

    # missing parts are not returned
    assert "1d1s" == "1s0m0h1d" |> to_ms!() |> to_string()

    # test with different numbers
    assert "1d2h3m4s" == "4s3m2h1d" |> to_ms!() |> to_string()

    # of course higher units are converted
    assert "2d1h" == "#{24 * 2 + 1}h" |> to_ms!() |> to_string()
  end

  test "to string with milliseconds" do
    # left milliseconds are returned if there are only milliseconds left

    # not returned because we have seconds
    ms = 500 + to_ms!("1d20s")
    assert "1d20s" == to_string(ms)

    # only milliseconds
    assert "500ms" == to_string(500)
  end

  test "to string verbose" do
    # plurals are correct
    assert "1 day 20 seconds" == "1d20s" |> to_ms!() |> to_string(:verbose)
    assert "2 days 1 second" == "2d1s" |> to_ms!() |> to_string(:verbose)

    assert "500 milliseconds" == to_string(500, :verbose)
    assert "1 millisecond" == to_string(1, :verbose)

    assert "2 days 1 second" == (("2d1s" |> to_ms!()) + 500) |> to_string(:verbose)
  end
end
