# Implementation based on gb_trees
defmodule TimeQueue do
  @moduledoc """
  This is the single module of the TimeQueue library.
  """
  require Record
  alias :gb_trees, as: Tree

  Record.defrecordp(:tqrec, tref: nil, val: nil)

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
  @opaque tref :: {pos_integer, integer}

  @opaque entry :: record(:tqrec, tref: tref, val: any)

  # @todo add values typing
  @opaque t :: Tree.tree(tref, any)

  defguardp is_timespec(timespec)
            when is_integer(elem(timespec, 0)) and elem(timespec, 1) in @timespec_units

  @doc """
  Creates an empty time queue.

      iex> tq = TimeQueue.new()
      iex> TimeQueue.peek(tq)
      :empty
  """
  @spec new :: t
  def new,
    do: Tree.empty()

  @doc """
  Returns the numer of entries in the queue.

  See `peek/2`.
  """
  @spec size(t) :: integer
  def size(tq),
    do: Tree.size(tq)

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

  def peek(tq, now) do
    if Tree.is_empty(tq) do
      :empty
    else
      case Tree.smallest(tq) do
        {{ts, _} = tref, val} when ts <= now -> {:ok, tqrec(tref: tref, val: val)}
        {{ts, _}, _} -> {:delay, ts - now}
      end
    end
  end

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
    if Tree.is_empty(tq) do
      :empty
    else
      case Tree.take_smallest(tq) do
        {{ts, _} = tref, val, tq2} when ts <= now -> {:ok, tqrec(tref: tref, val: val), tq2}
        {{ts, _}, _, _} -> {:delay, ts - now}
      end
    end
  end

  @doc """
  Deletes an entry from the queue and returns the new queue.

  It accepts a time reference or a full entry. In cas of an entry is
  given, only its time reference will be used to find the entry to 
  delete, meaning the queue entry will be deleted event if the value
  of the passed entry was changed.

  The function does not fail if the entry was not found and simply 
  returns the queue as-is.
  """
  @spec delete(t, entry | tref) :: t
  def delete(tq, tqrec(tref: tref)),
    do: delete(tq, tref)

  def delete(tq, {_, _} = tref),
    do: {:ok, Tree.delete_any(tref, tq)}

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
    tq = Tree.insert(tref, val, tq)
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
  def value(tqrec(val: val)), do: val

  @doc """
  Returns the time reference of an queue entry. This reference is
  used as a key to identify a unique entry.
      iex> tq = TimeQueue.new()
      iex> {:ok, tref, tq} = TimeQueue.enqueue(tq, 10, :my_value)
      iex> Process.sleep(10)
      iex> {:ok, entry} = TimeQueue.peek(tq)
      iex> tref == TimeQueue.tref(entry)
      true
  """
  @spec tref(entry) :: any
  def tref(tqrec(tref: tref)), do: tref

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
