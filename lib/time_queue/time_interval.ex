defmodule TimeQueue.TimeInterval do
  alias __MODULE__
  @enforce_keys [:ms]
  defstruct ms: 0

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

  def parse("-" <> bin) do
    parse(bin, true)
  end

  def parse(bin) do
    parse(bin, false)
  end

  def parse(bin, negative?) when is_binary(bin) do
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

  def parse!(bin) do
    case parse(bin) do
      {:ok, t} ->
        t

      {:error, {:cannot_parse_interval, _}} ->
        raise ArgumentError, ~s(cannot parse "#{bin}" as a time interval)
    end
  end

  def to_ms(%__MODULE__{ms: ms}),
    do: {:ok, ms}

  def to_ms(raw) when is_binary(raw) do
    with {:ok, parsed} <- parse(raw),
         do: to_ms(parsed)
  end

  def to_ms(raw) when is_integer(raw),
    do: {:ok, raw}

  def to_ms(raw),
    do: {:error, "expected integer or binary, got: #{raw}"}

  def to_ms!(bin) when is_binary(bin),
    do: bin |> parse!() |> Map.fetch!(:ms)

  def to_ms!(int) when is_integer(int),
    do: int

  def to_ms!(%__MODULE__{ms: ms}),
    do: ms

  defp calc_interval(digits, unit) when is_binary(digits),
    do: digits |> String.to_integer() |> calc_interval(unit)

  defp calc_interval(v, "d"), do: day(v)
  defp calc_interval(v, "h"), do: hour(v)
  defp calc_interval(v, "m"), do: minute(v)
  defp calc_interval(v, "s"), do: second(v)

  @ms 1
  @second 1000 * @ms
  @minute 60 * @second
  @hour 60 * @minute
  @day 24 * @hour

  def day(n), do: n * @day
  def hour(n), do: n * @hour
  def minute(n), do: n * @minute
  def second(n), do: n * @second

  @str_parts [{"d", @day}, {"h", @hour}, {"m", @minute}, {"s", @second}]

  @str_parts_verbose [
    {"day", "days", @day},
    {"hour", "hours", @hour},
    {"minute", "minutes", @minute},
    {"second", "seconds", @second}
  ]

  def to_string(ms) when is_integer(ms) do
    Enum.reduce(@str_parts, {[], ms}, fn {unit, val_of_unit}, {io, ms} ->
      if ms >= val_of_unit do
        {n, rest} = divrem(ms, val_of_unit)
        {[io, Integer.to_string(n), unit], rest}
      else
        {io, ms}
      end
    end)
    |> case do
      {[], ms} -> "#{ms}ms"
      {str, _} -> :erlang.iolist_to_binary(str)
    end
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

  def divrem(num, d) do
    {div(num, d), rem(num, d)}
  end
end
