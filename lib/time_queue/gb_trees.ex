# Implementation based on gb_trees
defmodule TimeQueue.GbTrees do
  @moduledoc """
  Implements a timers queue based on [gb_trees](http://erlang.org/doc/man/gb_trees.html).

  The queue keys are a two-tuple composed of the timestamp of an entry
  and an unique integer.

  No erlang timers or processes are used, as the queue is only a
  data structure. The advantage is that the queue can be persisted on
  storage and keep working after restarting the runtime. The queue
  maintain its own list of unique integers to avoir relying on BEAM
  unique integers as they are reset on restart.

  The main drawback is that the queue entries must be manually checked
  for expired timers.
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

  @opaque t :: {id, Tree.tree(tref, any)}
  @type timespec :: {pos_integer, timespec_unit}
  @type ttl :: timespec | integer
  @type timestamp_ms :: pos_integer
  @opaque tref :: {timestamp_ms, integer}
  @opaque id :: integer
  @opaque entry :: record(:tqrec, tref: tref, val: any)
  # @todo add values typing
  @type pop_return(tq) :: :empty | {:delay, tref(), non_neg_integer} | {:ok, entry(), tq}
  @type peek_return() :: :empty | {:delay, tref(), non_neg_integer} | {:ok, entry()}
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
      iex> TimeQueue.peek(tq)
      :empty
  """
  @spec new :: t
  def new,
    do: {@min_int, Tree.empty()}

  @doc """
  Returns the numer of entries in the queue.
  """
  @spec size(t) :: integer
  def size({_, tree}),
    do: Tree.size(tree)

  @doc """
  Returns the next event of the queue with the current system time as `now/0`.

  See `peek/2`.
  """
  @spec peek(t) :: peek_return()
  def peek(tq),
    do: peek(tq, now())

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
      iex> {:delay, ^tref, 80} = TimeQueue.peek(tq, _now = 20)
      iex> {:ok, _} = TimeQueue.peek(tq, _now = 100)
  """
  @spec peek(t, now_ms :: timestamp_ms) :: peek_return()
  def peek({_, tree}, now) do
    if Tree.is_empty(tree) do
      :empty
    else
      case Tree.smallest(tree) do
        {{ts, _} = tref, val} when ts <= now -> {:ok, tqrec(tref: tref, val: val)}
        {{ts, _} = tref, _} -> {:delay, tref, ts - now}
      end
    end
  end

  @doc """
  Extracts the next event of the queue with the current system time as `now/0`.

  See `pop/2`.
  """
  @spec pop(t) :: pop_return(t)
  def pop(tq),
    do: pop(tq, now())

  @doc """
  Extracts the next event of the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, entry, new_queue}` if the timestamp of the first entry is `<=` to the
    given current time. The entry is deleted from `new_queue`.
  - `{:delay, tref, ms}` if the timestamp of the first entry is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.pop(tq, _now = 20)
      iex> {:ok, _, _} = TimeQueue.pop(tq, _now = 100)
  """
  @spec pop(t, now_ms :: timestamp_ms) :: pop_return(t)
  def pop({max_id, tree}, now) do
    if Tree.is_empty(tree) do
      :empty
    else
      case Tree.smallest(tree) do
        {{ts, _}, _} when ts <= now ->
          {tref, val, tree2} = Tree.take_smallest(tree)
          {:ok, tqrec(tref: tref, val: val), {max_id, tree2}}

        {{ts, _} = tref, _} ->
          {:delay, tref, ts - now}
      end
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
  def delete(tq, tqrec(tref: tref)),
    do: delete(tq, tref)

  def delete({max_id, tree}, {_, _} = tref),
    do: {max_id, Tree.delete_any(tref, tree)}

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
  def enqueue_abs({max_id, tree}, ts, val) do
    new_max_id = bump_max_id(max_id)
    tref = {ts, new_max_id}
    tree = Tree.insert(tref, val, tree)
    {:ok, tref, {new_max_id, tree}}
  end

  defp bump_max_id(max_id) when max_id < @max_int, do: max_id + 1
  defp bump_max_id(@max_int), do: @min_int

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

  @doc """
  This function is used internally to determine the current time when it is
  not given in the arguments to `enqueue/3`, `pop/1` and `peek/1`.

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
end
