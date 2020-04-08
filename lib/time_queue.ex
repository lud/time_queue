# Current implementation is siply based on a sorted list. It would
# benefit from a proper implementation of abstract ptiority queue
defmodule TimeQueue do
  require Record

  Record.defrecord(:trec, tref: nil, val: nil)

  @ttl_units [
    # :millisecond, # no single millisecond
    :ms,
    :second,
    :seconds,
    :minute,
    :minutes,
    :hour,
    :hours,
    :day,
    :days,
    :week,
    :weeks
  ]

  @type time_unit ::
          :ms
          | :second
          | :seconds
          | :minute
          | :minutes
          | :hour
          | :hours
          | :day
          | :days
          | :week
          | :weeks

  @type ttl :: {pos_integer, time_unit}

  @opaque entry :: record(:trec, tref: {pos_integer, integer}, val: any)

  @opaque t :: [entry]
  @opaque tref :: {integer, integer}

  defguard is_ttl(ttl) when is_integer(elem(ttl, 0)) and elem(ttl, 1) in @ttl_units

  @spec new :: {:ok, t}
  def new(),
    do: []

  @spec peek(t) :: :empty | {:delay, non_neg_integer} | {:ok, entry}
  @spec peek(t, now_ms :: integer) ::
          :empty | {:delay, non_neg_integer} | {:ok, entry}
  def peek(tq, now \\ system_time())

  def peek([], _),
    do: :empty

  def peek([trec(tref: {ts, _}) = first | _tq], now) when ts <= now,
    do: {:ok, first}

  def peek([trec(tref: {ts, _}) | _tq], now),
    do: {:delay, ts - now}

  @spec pop(t) :: :empty | {:delay, non_neg_integer} | {:ok, TimeQueue.entry()}

  def pop(tq, now \\ system_time()) do
    with {:ok, entry} <- peek(tq, now) do
      tq = delete(tq, entry)
      {:ok, entry, tq}
    end
  end

  @spec delete(t, entry) :: t
  def delete(tq, entry) do
    tq -- [entry]
  end

  @spec enqueue(t, ttl, any, now :: integer) :: {:ok, tref, t}
  def enqueue(tq, ttl, val, now \\ system_time())

  def enqueue(tq, ttl, val, now) when is_ttl(ttl), do: enqueue_abs(tq, ttl_add(ttl, now), val)

  def enqueue(tq, ttl, val, now) when is_integer(ttl),
    do: enqueue_abs(tq, now + ttl, val)

  def enqueue_abs(tq, ts, val) do
    tref = {ts, :erlang.unique_integer()}
    entry = trec(tref: tref, val: val)
    tq = insert(tq, entry)
    {:ok, tref, tq}
  end

  defp insert([], entry), do: [entry]

  defp insert([trec(tref: {next, _}) = candidate | tq], trec(tref: {ts, _}) = entry)
       when next <= ts,
       do: [candidate | insert(tq, entry)]

  defp insert([trec(tref: {next, _}) = candidate | tq], trec(tref: {ts, _}) = entry)
       when next > ts,
       do: [entry, candidate | tq]

  @spec value(entry) :: any
  def value(trec(val: val)), do: val

  defp system_time(),
    do: :erlang.system_time(:millisecond)

  @spec ttl_to_milliseconds(ttl) :: number

  def ttl_to_milliseconds({n, :ms}) when is_integer(n) and n > 0,
    do: n

  def ttl_to_milliseconds({_, _} = ttl) when is_ttl(ttl),
    do: ttl_to_seconds(ttl) * 1000

  defp ttl_to_seconds({seconds, unit}) when unit in [:second, :seconds],
    do: seconds

  defp ttl_to_seconds({minutes, unit}) when unit in [:minute, :minutes],
    do: minutes * 60

  defp ttl_to_seconds({hours, unit}) when unit in [:hour, :hours],
    do: hours * 60 * 60

  defp ttl_to_seconds({days, unit}) when unit in [:day, :days],
    do: days * 24 * 60 * 60

  defp ttl_to_seconds({weeks, unit}) when unit in [:week, :weeks],
    do: weeks * 7 * 24 * 60 * 60

  defp ttl_to_seconds({_, unit}),
    do: raise("Unknown TTL unit: #{unit}")

  defp ttl_add(ttl, int),
    do: ttl_to_milliseconds(ttl) + int
end
