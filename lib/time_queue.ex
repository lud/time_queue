# Current implementation is siply based on a sorted list. It would
# benefit from a proper implementation of abstract ptiority queue
defmodule TimeQueue do
  @moduledoc """
  This is the single module of the TimeQueue library.

  Optimization may lead to a different data structure, but at the
  momement the time queue is implemented as a simple list were entries
  are sorted with timestamps.
  """
  require Record

  Record.defrecordp(:trec, tref: nil, val: nil)

  @timespec_units [
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

  @type timespec_unit ::
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

  @type timespec :: {pos_integer, timespec_unit}
  @type ttl :: timespec | integer

  @opaque entry :: record(:trec, tref: {pos_integer, integer}, val: any)

  @opaque t :: [entry]
  @opaque tref :: {integer, integer}

  defguardp is_timespec(timespec)
            when is_integer(elem(timespec, 0)) and elem(timespec, 1) in @timespec_units

  @doc """
  Creates an empty time queue.

      iex> tq = TimeQueue.new()
      []
      iex> TimeQueue.peek(tq)
      :empty
  """
  @spec new :: t
  def new,
    do: []

  @doc """
  Returns the next event of the queue with the current system time as `now`.

  See `peek/2`.
  """
  @spec peek(t) :: :empty | {:delay, non_neg_integer} | {:ok, entry}
  def peek(tq),
    do: peek(tq, system_time())

  @doc """
  Returns the next event of the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, entry}` if the timestamp of the first entry is `<=` to the given
    current time.
  - `{:delay, ms}` if the timestamp of the first entry is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, _tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> TimeQueue.peek(tq, _now = 20)
      {:delay, 80}
      iex> {:ok, _} = TimeQueue.peek(tq, _now = 100)
  """
  @spec peek(t, now_ms :: pos_integer) ::
          :empty | {:delay, non_neg_integer} | {:ok, entry}

  def peek([], _),
    do: :empty

  def peek([trec(tref: {ts, _}) = first | _tq], now) when ts <= now,
    do: {:ok, first}

  def peek([trec(tref: {ts, _}) | _tq], now),
    do: {:delay, ts - now}

  @doc """
  Extracts the next event of the queue with the current system time as `now`.

  See `pop/2`.
  """
  @spec pop(t) ::
          :empty | {:delay, non_neg_integer} | {:ok, TimeQueue.entry()}
  def pop(tq),
    do: pop(tq, system_time())

  @doc """
  Extracts the next event of the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, entry, new_queue}` if the timestamp of the first entry is `<=` to the
    given current time. The entry is deleted from `new_queue`.
  - `{:delay, ms}` if the timestamp of the first entry is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, _tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> TimeQueue.pop(tq, _now = 20)
      {:delay, 80}
      iex> {:ok, _, _} = TimeQueue.pop(tq, _now = 100)
  """
  @spec pop(t, now_ms :: pos_integer) ::
          :empty | {:delay, non_neg_integer} | {:ok, entry()}
  def pop(tq, now) do
    with {:ok, entry} <- peek(tq, now) do
      tq = delete(tq, entry)
      {:ok, entry, tq}
    end
  end

  @doc """
  Deletes an entry from the queue and returns the new queue.

  The function does not fail if the entry was not found and simply returns the
  queue as-is.
  """
  @spec delete(t, entry) :: t
  def delete(tq, trec() = entry),
    do: tq -- [entry]

  @doc """
  Adds a new entry to the queue with a TTL and the current system time as `now`.

  See `enqueue/4`.
  """
  @spec enqueue(t, ttl, any) :: {:ok, tref, t}
  def enqueue(tq, ttl, val),
    do: enqueue(tq, ttl, val, system_time())

  @doc """
  Adds a new entry to the queue with a TTL relative to the given timestamp in
  milliseconds.

  Returns `{:ok, tref, new_queue}` where `tref` is a timer reference (not
  used yed).
  """
  @spec enqueue(t, ttl, any, now :: integer) :: {:ok, tref, t}
  def enqueue(tq, ttl, val, now_ms)

  def enqueue(tq, ttl, val, now) when is_timespec(ttl),
    do: enqueue_abs(tq, timespec_add(ttl, now), val)

  def enqueue(tq, ttl, val, now) when is_integer(ttl),
    do: enqueue_abs(tq, now + ttl, val)

  @doc """
  Adds a new entry to the queue with an absolute timestamp.

  Returns `{:ok, tref, new_queue}` where `tref` is a timer reference (not
  used yed).
  """
  @spec enqueue_abs(t, end_time :: integer, value :: any) :: {:ok, tref, t}
  def enqueue_abs(tq, ts, val) do
    tref = {ts, :erlang.unique_integer()}
    entry = trec(tref: tref, val: val)
    tq = insert(tq, entry)
    {:ok, tref, tq}
  end

  @doc """
  Returns the value of an queue entry.
      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue(tq, 10, :my_value)
      iex> Process.sleep(10)
      iex> {:ok, entry} = TimeQueue.peek(tq)
      iex> TimeQueue.value(entry)
      :my_value
  """
  @spec value(entry) :: any
  def value(trec(val: val)), do: val

  defp insert([], entry),
    do: [entry]

  defp insert([trec(tref: {next, _}) = candidate | tq], trec(tref: {ts, _}) = entry)
       when next <= ts,
       do: [candidate | insert(tq, entry)]

  defp insert([trec(tref: {next, _}) = candidate | tq], trec(tref: {ts, _}) = entry)
       when next > ts,
       do: [entry, candidate | tq]

  defp system_time,
    do: :erlang.system_time(:millisecond)

  defp ttl_to_milliseconds({n, :ms}) when is_integer(n) and n > 0,
    do: n

  defp ttl_to_milliseconds({_, _} = ttl) when is_timespec(ttl),
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

  defp timespec_add(ttl, int),
    do: ttl_to_milliseconds(ttl) + int
end
