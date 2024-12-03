defmodule TimeQueue.TimeInterval do
  @moduledoc """
  Utility to parse and format time intervals represented as strings.

  A time interval is formatted as pairs of numbers and units. For instance
  `1d2h` is two pairs and means 1 day and 2 hours.

  The unit is always lowercase and one of:

  * `d` for day
  * `h` for hour
  * `m` for minute
  * `s` for second

  Note that the `ms` unit is not supported on parsing, but will be returned when
  formatting an interval (integer or struct) that is smaller than 1 second.

  There are a couple of rules regarding the format:

  * The order of the pairs is not significant. `1d2h` is the same as `2h1d`.
  * The addition is supported, _i.e._ the units are cumulative. `1d1d` is the
    same as `2d`.
  * The subtraction is not supported, each pair is absolute and just represent a
    quantity of milliseconds. But it is possible to prefix the expression with a
    `-`, which will make the parser return a negative value.  So `-1d1h` will
    return a negative number, but `1d-1h` or `1d-1d` are invalid.
  """

  alias __MODULE__
  @enforce_keys [:ms]
  defstruct ms: 0

  @type t :: %__MODULE__{ms: integer}

  # Returns the total interval sum in millisecond
  #
  # Format of interval: <optional-negative-sign><digits><unit>[<digits><unit>[ … ]], eg: 15d2h3m
  # Order of elements is not significant: 1d2h == 2h1d
  # Units:
  # - d Day
  # - h Hour
  # - m Minute
  # - s Second
  # Unimplemented Units:
  # - w Week
  # - b Month
  # - y Year
  # - x millisecond
  @re_all_intervals ~r/^(([0-9]+)(d|h|m|s))+$/
  @re_interval ~r/([0-9]+)(d|h|m|s)+/

  @ms 1
  @second 1000 * @ms
  @minute 60 * @second
  @hour 60 * @minute
  @day 24 * @hour

  @doc """
  Returns a `%#{inspect(__MODULE__)}{}` struct from a time interval string.

  ### Examples
      iex> TimeInterval.parse("1d1h")
      {:ok, %TimeQueue.TimeInterval{ms: 90000000}}

      iex> TimeInterval.parse("some gibberish")
      {:error, {:cannot_parse_interval, "some gibberish"}}
  """
  @spec parse(binary) :: {:ok, t} | {:error, {:cannot_parse_interval, binary}}
  def parse("-" <> bin) do
    parse(bin, true)
  end

  def parse(bin) do
    parse(bin, false)
  end

  defp parse(bin, negative?) when is_binary(bin) do
    if Regex.match?(@re_all_intervals, bin) do
      matches = Regex.scan(@re_interval, bin, capture: :all_but_first)

      sum_ms =
        Enum.reduce(matches, 0, fn [digits, unit], acc ->
          acc + calc_interval(digits, unit)
        end)

      ms = if negative?, do: -1 * sum_ms, else: sum_ms

      {:ok, %TimeInterval{ms: ms}}
    else
      {:error, {:cannot_parse_interval, bin}}
    end
  end

  @doc """
  Same as `parse/1` but returns the struct directly or raises an
  `ArgumentError`.

  ### Example

      iex> TimeInterval.parse!("1d1h")
      %TimeQueue.TimeInterval{ms: 90000000}
  """
  @spec parse(binary) :: t
  def parse!(bin) do
    case parse(bin) do
      {:ok, t} ->
        t

      {:error, {:cannot_parse_interval, _}} ->
        raise ArgumentError, ~s(cannot parse "#{bin}" as a time interval)
    end
  end

  @doc """
  Returns the number of milliseconds in the given interval, wrapped in an
  `:ok` tuple, or an `:error` tuple. The interval can be a string or a
  `%#{inspect(TimeInterval)}{}` struct.

  For convenience reasons, this function also accepts integers, which are
  returned as is.

  ### Examples

      iex> TimeInterval.to_ms("1d1h")
      {:ok, 90000000}

      iex> "1d1h" |> TimeInterval.parse!() |> TimeInterval.to_ms()
      {:ok, 90000000}

      iex> TimeInterval.to_ms("some gibberish")
      {:error, {:cannot_parse_interval, "some gibberish"}}

      iex> TimeInterval.to_ms(1234)
      {:ok, 1234}
  """
  @spec to_ms(binary | integer | t) :: {:ok, integer} | {:error, {:cannot_parse_interval, binary}}
  def to_ms(%__MODULE__{ms: ms}),
    do: {:ok, ms}

  def to_ms(raw) when is_binary(raw) do
    with {:ok, parsed} <- parse(raw),
         do: to_ms(parsed)
  end

  def to_ms(raw) when is_integer(raw),
    do: {:ok, raw}

  @doc """
  Same as `to_ms/1` but returns the number of milliseconds directly or raises an
  `ArgumentError`.
  """
  @spec to_ms(binary | integer | t) :: integer
  def to_ms!(bin) when is_binary(bin),
    do: bin |> parse!() |> Map.fetch!(:ms)

  def to_ms!(int) when is_integer(int),
    do: int

  def to_ms!(%__MODULE__{ms: ms}),
    do: ms

  defp calc_interval(digits, unit) when is_binary(digits),
    do: digits |> String.to_integer() |> calc_interval(unit)

  defp calc_interval(v, "d"), do: days(v)
  defp calc_interval(v, "h"), do: hours(v)
  defp calc_interval(v, "m"), do: minutes(v)
  defp calc_interval(v, "s"), do: seconds(v)

  @doc "Returns the number of milliseconds in `n` days."
  def days(n), do: n * @day
  @doc "Returns the number of milliseconds in `n` hours. Alias for `:timer.hours/1`."
  def hours(n), do: n * @hour
  @doc "Returns the number of milliseconds in `n` minutes. Alias for `:timer.minutes/1`."
  def minutes(n), do: n * @minute
  @doc "Returns the number of milliseconds in `n` seconds. Alias for `:timer.seconds/1`."
  def seconds(n), do: n * @second

  @doc false
  def day(n), do: days(n)
  @doc false
  def hour(n), do: hours(n)
  @doc false
  def minute(n), do: minutes(n)
  @doc false
  def second(n), do: seconds(n)

  @str_parts_verbose [
    {"day", "days", @day},
    {"hour", "hours", @hour},
    {"minute", "minutes", @minute},
    {"second", "seconds", @second}
  ]

  @doc """
  Returns the string representation of the given time interval. Note that as
  this module is intended to work with long durations, the number of remaining
  milliseconds after having computed the days, hours, minutes and seconds, is
  discarded.


  ### Examples

      iex> "1d1h" |> TimeInterval.parse!() |> TimeInterval.to_string()
      "1d1h"

      iex> "1d1d1d" |> TimeInterval.parse!() |> TimeInterval.to_string()
      "3d"

      iex> TimeInterval.to_string(90000000)
      "1d1h"

      iex> TimeInterval.to_string(90000123) # Discared remaining milliseconds
      "1d1h"

      iex> TimeInterval.to_string(123) # Smaller than 1 second
      "123ms"
  """
  @spec to_string(t | integer) :: binary
  def to_string(time_interval)

  def to_string(%__MODULE__{ms: ms}) do
    __MODULE__.to_string(ms)
  end

  def to_string(ms) when is_integer(ms) do
    ms |> int_to_string(:noskip) |> :erlang.iolist_to_binary()
  end

  defp int_to_string(ms, :noskip) when ms < 1000, do: [Integer.to_string(ms), "ms"]
  defp int_to_string(ms, :skip) when ms < 1000, do: []

  defp int_to_string(ms, _) when ms >= @day do
    days = div(ms, @day)
    ms = rem(ms, @day)

    [Integer.to_string(days), "d" | int_to_string(ms, :skip)]
  end

  defp int_to_string(ms, _) when ms >= @hour do
    hours = div(ms, @hour)
    ms = rem(ms, @hour)

    [Integer.to_string(hours), "h" | int_to_string(ms, :skip)]
  end

  defp int_to_string(ms, _) when ms >= @minute do
    minutes = div(ms, @minute)
    ms = rem(ms, @minute)

    [Integer.to_string(minutes), "m" | int_to_string(ms, :skip)]
  end

  defp int_to_string(ms, _) when ms >= @second do
    seconds = div(ms, @second)

    # discard remaining ms

    [Integer.to_string(seconds), "s"]
  end

  @doc """

  Returns the string representation with the same rules as in `to_string/1` but
  in long form.

  ### Example

      iex> "1d1h" |> TimeInterval.parse!() |> TimeInterval.to_string(:verbose)
      "1 day 1 hour"
  """
  @spec to_string(t | integer, :verbose) :: binary
  def to_string(%__MODULE__{ms: ms}, :verbose) do
    __MODULE__.to_string(ms, :verbose)
  end

  def to_string(ms, :verbose) when is_integer(ms) do
    Enum.reduce(@str_parts_verbose, {[], ms}, fn {singular, plural, val_of_unit}, {io, ms} ->
      if ms >= val_of_unit do
        {n, rest} = divrem(ms, val_of_unit)

        name =
          case n do
            1 -> singular
            _ -> plural
          end

        padding =
          case {rest, val_of_unit} do
            {_, @second} -> []
            {0, _} -> []
            _ -> " "
          end

        {[io, Integer.to_string(n), " ", name, padding], rest}
      else
        {io, ms}
      end
    end)
    |> case do
      {[], 1} -> "1 millisecond"
      {[], ms} -> "#{ms} milliseconds"
      {str, _} -> :erlang.iolist_to_binary(str)
    end
  end

  defp divrem(num, d) do
    {div(num, d), rem(num, d)}
  end
end
