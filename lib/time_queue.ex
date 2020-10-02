defmodule TimeQueue do
  @moduledoc """
  Implements a timers queue based on a list of maps. The queue can be encoded
  as JSON.

  The performance will be worse for large queues in regard to the previous
  gb_trees based implementation, although the difference is negligible for
  small queues (<= 1000 entries).

  All map keys are shrinked to a single letter as this queue is intended to
  be encoded and published to HTTP clients over the wire, mutiple times.

  The queue keys are a map composed of the timestamp (`t`) of an entry
  and an unique integer (`u`).

  No erlang timers or processes are used, as the queue is only a
  data structure. The advantage is that the queue can be persisted on
  storage and keeps working after restarting the runtime. The queue
  maintain its own list of unique integers to avoir relying on BEAM
  unique integers as they are reset on VM restarts.

  The main drawback of a functional queue is that the queue entries must be
  manually checked for expired timers.
  """

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

  @opaque t :: %{m: max_id :: integer, s: size :: non_neg_integer, q: list(entry)}
  @type entry_value :: any
  @opaque entry :: %{k: tref, v: entry_value}
  @type timespec :: {pos_integer, timespec_unit}
  @type ttl :: timespec | integer
  @type timestamp_ms :: pos_integer
  @opaque tref :: %{t: timestamp_ms, u: integer}
  @type pop_return() :: :empty | {:delay, tref(), non_neg_integer} | {:ok, entry_value, t}
  @type peek_return() :: :empty | {:delay, tref(), non_neg_integer} | {:ok, entry_value}
  @type peek_entry_return() :: :empty | {:delay, tref(), non_neg_integer} | {:ok, entry}
  @type pop_entry_return() :: :empty | {:delay, tref(), non_neg_integer} | {:ok, entry, t}
  @type enqueue_return(tq) :: {:ok, tref, tq}

  # If we reach the @max_int for the keys, we will start over at @min_int.
  # Hopefully in the meantime they will be no tref stored that would match any
  # tref created with the same timestamp and the same ref (very unlikely !).
  # We have to do this though because the time queue must be persistable, so
  # unique integers must remain unique even if we are restarting the runtime ;
  # and timestamps can be manually set to any values, for example with small
  # integers like (1, 2, 3) when modeling a discrete time (in steps).
  #
  # We use 32b integers to keep low data size when using external term format.
  @min_int -2_147_483_648
  @max_int 2_147_483_647

  defguardp is_timespec(timespec)
            when is_integer(elem(timespec, 0)) and elem(timespec, 1) in @timespec_units

  @doc """
  Creates an empty time queue.

      iex> tq = TimeQueue.new()
      iex> TimeQueue.peek_entry(tq)
      :empty
  """
  @spec new :: t
  def new,
    do: %{m: @min_int, s: 0, q: []}

  @doc """
  Returns the numer of entries in the queue.
  """
  @spec size(t) :: integer
  def size(%{s: s}),
    do: s

  @doc """
  Returns the next value of the queue with the current system time as `now/0`.

  See `peek/2`.
  """
  @spec peek(t) :: peek_return()
  def peek(tq),
    do: peek(tq, now())

  @doc """
  Returns the next value of the queue according to the given current time in
  milliseconds.

  Just like `pop/2` _vs._ `pop_entry/2`, `peek` wil only return `{:ok, value}`
  when a timeout is reached whereas `peek_entry` will return `{:ok, entry}`.
  """
  @spec peek(t, now_ms :: timestamp_ms) :: peek_return()
  def peek(tq, now) do
    case peek_entry(tq, now) do
      {:ok, entry} -> {:ok, value(entry)}
      other -> other
    end
  end

  @doc """
  Returns the next event of the queue with the current system time as `now/0`.

  See `peek_entry/2`.
  """
  @spec peek_entry(t) :: peek_entry_return()
  def peek_entry(tq),
    do: peek_entry(tq, now())

  @doc """
  Returns the next event of the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, entry}` if the timestamp of the first entry is `<=` to the given
    current time.
  - `{:delay, tref, ms}` if the timestamp of the first entry is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.peek_entry(tq, _now = 20)
      iex> {:ok, _} = TimeQueue.peek_entry(tq, _now = 100)
  """
  @spec peek_entry(t, now_ms :: timestamp_ms) :: peek_entry_return()
  def peek_entry(%{s: 0}, _),
    do: :empty

  def peek_entry(%{q: [h | _]}, now) do
    case h do
      %{k: %{t: ts}} = entry when ts <= now -> {:ok, entry}
      %{k: %{t: ts} = tref} -> {:delay, tref, ts - now}
    end
  end

  @doc """
  Extracts the next entry in the queue with the current system time as `now/0`.

  See `pop/2`.
  """
  @spec pop(t) :: pop_return()
  def pop(tq),
    do: pop(tq, now())

  @doc ~S"""
  Extracts the next entry in the queue according to the given current time in
  milliseconds. 

  Much like `pop_entry/2` but the tuple returned when an entry time is reached
  (returns with `:ok`) success will only contain the value inserted in the
  queue.

  Possible return values are:

  - `:empty`
  - `{:ok, value, new_queue}` if the timestamp of the first entry is `<=` to the
    given current time. The entry is deleted from `new_queue`.
  - `{:delay, tref, ms}` if the timestamp of the first entry is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.pop(tq, _now = 20)
      iex> {:ok, value, _} = TimeQueue.pop(tq, _now = 100)
      iex> value
      :hello
  """

  @spec pop(t, now_ms :: timestamp_ms) :: pop_return()
  def pop(tq, now) do
    case pop_entry(tq, now) do
      {:ok, entry, tq2} -> {:ok, value(entry), tq2}
      other -> other
    end
  end

  @doc """
  Extracts the next entry in the queue with the current system time as `now/0`.

  See `pop_entry/2`.
  """
  @spec pop_entry(t) :: pop_entry_return()
  def pop_entry(tq),
    do: pop_entry(tq, now())

  @doc ~S"""
  Extracts the next entry in the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, entry, new_queue}` if the timestamp of the first entry is `<=` to the
    given current time. The entry is deleted from `new_queue`.
  - `{:delay, tref, ms}` if the timestamp of the first entry is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.pop_entry(tq, _now = 20)
      iex> {:ok, entry, _} = TimeQueue.pop_entry(tq, _now = 100)
      iex> TimeQueue.value(entry)
      :hello
  """
  @spec pop_entry(t, now_ms :: timestamp_ms) :: pop_entry_return()
  def pop_entry(%{s: 0}, _),
    do: :empty

  def pop_entry(%{s: size, q: [h | tail]} = tq, now) do
    case h do
      %{k: %{t: ts}} = entry when ts <= now ->
        tq = %{tq | s: size - 1, q: tail}
        {:ok, entry, tq}

      %{k: %{t: ts} = tref} ->
        {:delay, tref, ts - now}
    end
  end

  @doc """
  Deletes an entry from the queue and returns the new queue.

  It accepts a time reference or a full entry. When an entry is given,
  its time reference will be used to find the entry to  delete,
  meaning the queue entry will be deleted even if the value of the
  passed entry was tampered.

  The function does not fail if the entry cannot be found and simply
  returns the queue as-is.
  """
  @spec delete(t, entry | tref) :: t
  def delete(tq, %{k: tref}),
    do: delete(tq, tref)

  def delete(tq, %{t: _, u: _} = tref),
    do: filter(tq, fn %{k: k} -> k != tref end)

  @doc """
  Deletes all entries from the queue whose values are equal to `unwanted`.
  """
  @spec delete_val(t, any) :: t
  def delete_val(tq, unwanted) do
    filter(tq, fn %{v: v} -> v !== unwanted end)
  end

  @doc """
  Returns a new queue with entries for whom the given callback returned a truthy
  value.

  Use `filter_val/2` to filter only using values.
  """
  @spec filter(t, (entry -> bool)) :: t
  def filter(%{q: q} = tq, fun) do
    new_q = Enum.filter(q, fun)
    %{tq | s: length(new_q), q: new_q}
  end

  @doc """
  Returns a new queue with entries for whom the given callback returned a truthy
  value.

  Unlinke `filter/2`, the callback is only passed the entry value.
  """
  @spec filter_val(t, (any -> bool)) :: t
  def filter_val(tq, fun) do
    filter(tq, fn %{v: v} -> fun.(v) end)
  end

  @doc """
  Adds a new entry to the queue with a TTL and the current system time as `now/0`.

  See `enqueue/4`.
  """
  @spec enqueue(t, ttl, any) :: enqueue_return(t)
  def enqueue(tq, ttl, val),
    do: enqueue(tq, ttl, val, now())

  @doc """
  Adds a new entry to the queue with a TTL relative to the given timestamp in
  milliseconds.

  Returns `{:ok, tref, new_queue}` where `tref` is a timer reference.
  """
  @spec enqueue(t, ttl, any, now :: integer) :: enqueue_return(t)
  def enqueue(tq, ttl, val, now_ms)

  def enqueue(tq, ttl, val, now) when is_timespec(ttl),
    do: enqueue_abs(tq, timespec_add(ttl, now), val)

  def enqueue(tq, ttl, val, now) when is_integer(ttl),
    do: enqueue_abs(tq, now + ttl, val)

  @doc """
  Adds a new entry to the queue with an absolute timestamp.

  Returns `{:ok, tref, new_queue}` where `tref` is a timer reference.
  """
  @spec enqueue_abs(t, end_time :: integer, value :: any) :: enqueue_return(t)
  def enqueue_abs(%{m: max_id, s: size, q: q} = tq, ts, val) do
    new_max_id = bump_max_id(max_id)
    tref = %{t: ts, u: new_max_id}
    entry = %{k: tref, v: val}
    q = insert(q, entry)
    {:ok, tref, %{tq | s: size + 1, q: q, m: new_max_id}}
  end

  defp insert([%{k: ktop} = top | rest], %{k: k} = cur) when k > ktop do
    [top | insert(rest, cur)]
  end

  defp insert(list, cur) do
    [cur | list]
  end

  defp bump_max_id(max_id) when max_id < @max_int, do: max_id + 1
  defp bump_max_id(@max_int), do: @min_int

  @doc """
  Returns the value of an queue entry.
      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue(tq, 10, :my_value)
      iex> Process.sleep(10)
      iex> {:ok, entry} = TimeQueue.peek_entry(tq)
      iex> TimeQueue.value(entry)
      :my_value
  """
  @spec value(entry) :: any
  def value(%{v: val}), do: val

  @doc """
  Returns the time reference of an queue entry. This reference is
  used as a key to identify a unique entry.
      iex> tq = TimeQueue.new()
      iex> {:ok, tref, tq} = TimeQueue.enqueue(tq, 10, :my_value)
      iex> Process.sleep(10)
      iex> {:ok, entry} = TimeQueue.peek_entry(tq)
      iex> tref == TimeQueue.tref(entry)
      true
  """
  @spec tref(entry) :: any
  def tref(%{k: tref}), do: tref

  @doc """
  This function is used internally to determine the current time when it is not
  given in the arguments to `enqueue/3`, `pop/1`, `pop_entry/1` and `peek_entry/1`.

  It is a simple alias to `:erlang.system_time(:millisecond)`. TimeQueue does
  not use monotonic time since it already manages its own unique identifiers for
  queue entries.
  """
  @spec now :: integer
  def now(),
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

  def supports_encoding(:json), do: true
  def supports_encoding(:etf), do: true
  def supports_encoding(_), do: false
end
