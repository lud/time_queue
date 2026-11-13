defmodule TimeQueue do
  @moduledoc """
  Implements a timers queue based on
  [gb_trees](https://www.erlang.org/doc/apps/stdlib/gb_trees.html). The queue
  can be encoded as JSON with `Jason` or Elixir's `JSON` module, and `dump/1`
  returns the same data as plain maps and lists for any other encoder.

  All map keys in the encoded form are shrinked to a single letter as this
  queue is intended to be encoded and published to HTTP clients over the wire,
  multiple times.

  The queue keys are a map composed of the timestamp (`t`) of an event
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

  @opaque t :: %__MODULE__{max_id: integer, tree: :gb_trees.tree(tref, event_value)}
  @type event_value :: any
  @opaque event :: %{k: tref, v: event_value}
  @type timespec :: {integer, timespec_unit}
  @type ttl :: timespec | integer
  @type timestamp_ms :: integer
  @opaque tref :: %{t: timestamp_ms, u: integer}
  @type dumped :: %{
          m: integer,
          s: non_neg_integer,
          q: [%{k: %{t: timestamp_ms, u: integer}, v: event_value}]
        }

  # If we reach the @max_int for the keys, we will start over at @min_int.
  # Hopefully in the meantime they will be no tref stored that would match any
  # tref created with the same timestamp and the same ref (very unlikely !).
  # We have to do this though because the time queue must be persistable, so
  # unique integers must remain unique even if we are restarting the runtime.
  #
  # We use 32b integers to keep low data size when using external term format.
  @min_int -2_147_483_648
  @max_int 2_147_483_647

  @enforce_keys [:max_id, :tree]
  defstruct @enforce_keys

  @empty_tree :gb_trees.empty()

  @max_timeout 4_294_967_295

  defguardp is_timespec(timespec)
            when is_integer(elem(timespec, 0)) and elem(timespec, 1) in @timespec_units

  @doc """
  Creates an empty time queue.

      iex> tq = TimeQueue.new()
      iex> TimeQueue.peek_event(tq)
      :empty
  """
  @spec new :: t
  def new,
    do: %__MODULE__{max_id: @min_int, tree: :gb_trees.empty()}

  @doc """
  Returns the number of entries in the queue.
  """
  @spec size(t) :: integer
  def size(tq)

  def size(%__MODULE__{tree: tree}),
    do: :gb_trees.size(tree)

  @doc """
  Returns the next value of the queue or a delay in milliseconds before the next
  value.

  See `peek/2`.
  """
  @spec peek(t) :: :empty | {:delay, tref, non_neg_integer} | {:ok, event_value}
  def peek(tq),
    do: peek(tq, now())

  @doc """
  Returns the next value of the queue, or a delay, according to the given
  current time in milliseconds.

  Just like `pop/2` _vs._ `pop_event/2`, `peek` wil only return `{:ok, value}`
  when a timeout is reached whereas `peek_event` will return `{:ok, event}`.
  """
  @spec peek(t, now :: timestamp_ms) ::
          :empty | {:delay, tref, non_neg_integer} | {:ok, event_value}
  def peek(tq, now) do
    case peek_event(tq, now) do
      {:ok, event} -> {:ok, value(event)}
      other -> other
    end
  end

  @doc """
  Returns the next event of the queue or a delay in milliseconds before the next
  value.

  event values can be retrieved with `TimeQueue.value/1`.

  See `peek_event/2`.
  """
  @spec peek_event(t) :: :empty | {:delay, tref, non_neg_integer} | {:ok, event}
  def peek_event(tq),
    do: peek_event(tq, now())

  @doc """
  Returns the next event of the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, event}` if the timestamp of the first event is `<=` to the given
    current time.
  - `{:delay, tref, ms}` if the timestamp of the first event is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.peek_event(tq, _now = 20)
      iex> {:ok, _} = TimeQueue.peek_event(tq, _now = 100)
  """
  @spec peek_event(t, now :: timestamp_ms) ::
          :empty | {:delay, tref, non_neg_integer} | {:ok, event}
  def peek_event(tq, now)

  def peek_event(%__MODULE__{tree: @empty_tree}, _),
    do: :empty

  def peek_event(%__MODULE__{tree: tree}, now) do
    case :gb_trees.smallest(tree) do
      {%{t: ts} = tref, val} when ts <= now -> {:ok, event(tref, val)}
      {%{t: ts} = tref, _} -> {:delay, tref, ts - now}
    end
  end

  @doc """
  Extracts the next event in the queue or returns a delay.

  See `pop/2`.
  """
  @spec pop(t) :: :empty | {:delay, tref, non_neg_integer} | {:ok, event_value, t}
  def pop(tq),
    do: pop(tq, now())

  @doc """
  Extracts the next event in the queue according to the given current time in
  milliseconds.

  Much like `pop_event/2` but the tuple returned when an event time is reached
  (returns with `:ok`) success will only contain the value inserted in the
  queue.

  Possible return values are:

  - `:empty`
  - `{:ok, value, new_queue}` if the timestamp of the first event is `<=` to the
    given current time. The event is deleted from `new_queue`.
  - `{:delay, tref, ms}` if the timestamp of the first event is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.pop(tq, _now = 20)
      iex> {:ok, value, _} = TimeQueue.pop(tq, _now = 100)
      iex> value
      :hello
  """
  @spec pop(t, now :: timestamp_ms) ::
          :empty | {:delay, tref, non_neg_integer} | {:ok, event_value, t}
  def pop(tq, now) do
    case pop_event(tq, now) do
      {:ok, event, tq2} -> {:ok, value(event), tq2}
      other -> other
    end
  end

  @doc """
  Extracts the next event in the queue with the current system time as `now/0`.

  See `pop_event/2`.
  """
  @spec pop_event(t) :: :empty | {:delay, tref, non_neg_integer} | {:ok, event, t}
  def pop_event(tq),
    do: pop_event(tq, now())

  @doc """
  Extracts the next event in the queue according to the given current time in
  milliseconds.

  Possible return values are:

  - `:empty`
  - `{:ok, event, new_queue}` if the timestamp of the first event is `<=` to the
    given current time. The event is deleted from `new_queue`.
  - `{:delay, tref, ms}` if the timestamp of the first event is `>` to the given
    current time. The remaining amount of milliseconds is returned.

  ### Example

      iex> {:ok, tref, tq} = TimeQueue.new() |> TimeQueue.enqueue(100, :hello, _now = 0)
      iex> {:delay, ^tref, 80} = TimeQueue.pop_event(tq, _now = 20)
      iex> {:ok, event, _} = TimeQueue.pop_event(tq, _now = 100)
      iex> TimeQueue.value(event)
      :hello
  """
  @spec pop_event(t, now :: timestamp_ms) ::
          :empty | {:delay, tref, non_neg_integer} | {:ok, event, t}
  def pop_event(%__MODULE__{tree: @empty_tree}, _),
    do: :empty

  def pop_event(%__MODULE__{tree: tree} = tq, now) do
    case :gb_trees.take_smallest(tree) do
      {%{t: ts} = tref, val, tree} when ts <= now ->
        {:ok, event(tref, val), %{tq | tree: tree}}

      {%{t: ts} = tref, _, _} ->
        {:delay, tref, ts - now}
    end
  end

  @doc """
  Deletes an event from the queue and returns the new queue.

  It accepts a time reference or a full event. When an event is given,
  its time reference will be used to find the event to  delete,
  meaning the queue event will be deleted even if the value of the
  passed event was tampered.

  The function does not fail if the event cannot be found and simply
  returns the queue as-is.
  """
  @spec delete(t, event | tref) :: t
  def delete(tq, %{k: tref}),
    do: delete(tq, tref)

  def delete(%__MODULE__{tree: tree} = tq, %{t: _, u: _} = tref),
    do: %{tq | tree: :gb_trees.delete_any(tref, tree)}

  @doc """
  Deletes all entries from the queue whose values are equal to `unwanted`.
  """
  @spec delete_val(t, any) :: t
  def delete_val(tq, unwanted) do
    filter_entries(tq, fn {_, v} -> v !== unwanted end)
  end

  @doc """
  Returns a new queue with entries for whom the given callback returned a truthy
  value.

  Use `filter_val/2` to filter only using values.
  """
  @spec filter(t, (event -> boolean)) :: t
  def filter(tq, fun) do
    filter_entries(tq, fn {tref, val} -> fun.(event(tref, val)) end)
  end

  @doc """
  Returns a new queue with entries for whom the given callback returned a truthy
  value.

  Unlinke `filter/2`, the callback is only passed the event value.
  """
  @spec filter_val(t, (any -> boolean)) :: t
  def filter_val(tq, fun) do
    filter_entries(tq, fn {_, v} -> fun.(v) end)
  end

  defp filter_entries(%__MODULE__{tree: tree} = tq, fun) do
    tree =
      tree
      |> :gb_trees.to_list()
      |> Enum.filter(fun)
      |> :gb_trees.from_orddict()

    %{tq | tree: tree}
  end

  @doc """
  Adds a new event to the queue with a TTL and the current system time as `now/0`.

  See `enqueue/4`.
  """
  @spec enqueue(t, ttl, any) :: {:ok, tref, t}
  def enqueue(tq, ttl, val),
    do: enqueue(tq, ttl, val, now())

  @doc """
  Adds a new event to the queue with a TTL relative to the given timestamp in
  milliseconds.

  The TTL is either an integer number of milliseconds, or a `{count, unit}`
  tuple where `unit` is one of `:ms`, `:second`, `:minute`, `:hour`, `:day` or
  `:week` (plural forms such as `:seconds` are accepted too).

  Returns `{:ok, tref, new_queue}` where `tref` is a timer reference.

  The TTL can be zero or negative. The event is then scheduled at or before
  `now` and is due immediately: `pop/2` returns it and `timeout/3` returns `0`.
  Events keep their real scheduled timestamp, so overdue events are returned in
  timestamp order, the oldest first. This lets you compute a TTL from a deadline
  that may already have passed and still handle the event right away.

      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue(tq, {-1, :second}, :due_1s_ago, _now = 10_000)
      iex> {:ok, _, tq} = TimeQueue.enqueue(tq, -5000, :due_5s_ago, _now = 10_000)
      iex> TimeQueue.timeout(tq, _now = 10_000)
      0
      iex> {:ok, first, tq} = TimeQueue.pop(tq, _now = 10_000)
      iex> {:ok, second, _} = TimeQueue.pop(tq, _now = 10_000)
      iex> {first, second}
      {:due_5s_ago, :due_1s_ago}
  """
  @spec enqueue(t, ttl, any, now :: integer) :: {:ok, tref, t}
  def enqueue(tq, ttl, val, now)

  def enqueue(tq, ttl, val, now) when is_timespec(ttl),
    do: enqueue_abs(tq, timespec_add(ttl, now), val)

  def enqueue(tq, ttl, val, now) when is_integer(ttl),
    do: enqueue_abs(tq, now + ttl, val)

  @doc """
  Adds a new event to the queue with an absolute timestamp.

  Returns `{:ok, tref, new_queue}` where `tref` is a timer reference.

  The timestamp can be in the past. The event is then due immediately, and
  overdue events are returned in timestamp order. See `enqueue/4`.
  """
  @spec enqueue_abs(t, end_time :: integer, value :: any) :: {:ok, tref, t}
  def enqueue_abs(%__MODULE__{max_id: max_id, tree: tree} = tq, ts, val) do
    new_max_id = bump_max_id(max_id)
    tref = %{t: ts, u: new_max_id}
    {:ok, tref, %{tq | max_id: new_max_id, tree: :gb_trees.insert(tref, val, tree)}}
  end

  defp bump_max_id(max_id) when max_id < @max_int, do: max_id + 1
  defp bump_max_id(@max_int), do: @min_int

  @doc """
  Returns the value of a queue event.
      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue(tq, 10, :my_value)
      iex> Process.sleep(10)
      iex> {:ok, event} = TimeQueue.peek_event(tq)
      iex> TimeQueue.value(event)
      :my_value
  """
  @spec value(event) :: any
  def value(event)

  def value(%{v: val}),
    do: val

  @doc """
  Returns the absolute timestamp a queue event is scheduled for.
      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 1234, :my_value)
      iex> {:ok, event} = TimeQueue.peek_event(tq)
      iex> TimeQueue.timestamp(event)
      1234
  """
  @spec timestamp(event) :: timestamp_ms
  def timestamp(event)

  def timestamp(%{k: %{t: ts}}),
    do: ts

  @doc """
  Returns the time reference of a queue event. This reference is
  used as a key to identify a unique event.
      iex> tq = TimeQueue.new()
      iex> {:ok, tref, tq} = TimeQueue.enqueue(tq, 10, :my_value)
      iex> Process.sleep(10)
      iex> {:ok, event} = TimeQueue.peek_event(tq)
      iex> tref == TimeQueue.tref(event)
      true
  """
  @spec tref(event) :: any
  def tref(event)

  def tref(%{k: tref}),
    do: tref

  @doc """
  Returns the time to next event.

  Same as `timeout(tq, :infinity, now())`. See `timeout/3`.
  """
  def timeout(tq) do
    timeout(tq, :infinity, now())
  end

  @doc """
  Returns the time to next event.

  Accepts either the current time or an atom to return when the queue is empty.

  * If an integer is given, it will has the same result as `timeout(tq, :infinity, integer)`.
  * If an atom is given, it will has the same result as `timeout(tq, atom, now())`.

  See `timeout/3`.
  """
  def timeout(tq, now) when is_integer(now) do
    timeout(tq, :infinity, now)
  end

  def timeout(tq, if_empty) when is_atom(if_empty) do
    timeout(tq, if_empty, now())
  end

  @doc """
  Provides a `GenServer` compatible timeout from the queue, giving the time to
  the next event.

  Accepts the current time as a third argument or will default to the current
  system time.

  Returns:
  * `if_empty` when the queue is empty. A common value in that case is either
    `:infinity` or `:hibernate`.
  * `0` when there the next event time has been reached.
  * The delay to the next event otherwise, capped at `4_294_967_295`
    milliseconds (about 49.7 days), the largest timeout accepted by `receive`
    and `GenServer`.

  When the next event is further away than that limit, the process wakes up
  before the event is due. `pop/1` then returns `{:delay, tref, ms}` with the
  full remaining delay, and calling `timeout/3` again gives the next wait.
  Always handle the `{:delay, tref, ms}` return of `pop/1` after a timeout.

      iex> {:ok, _, tq} = TimeQueue.enqueue(TimeQueue.new(), {60, :days}, :later, _now = 0)
      iex> TimeQueue.timeout(tq, _now = 0)
      4_294_967_295
      iex> {:delay, _, ms} = TimeQueue.pop(tq, _now = 0)
      iex> ms
      5_184_000_000

  For instance, when used in a `GenServer`, this function can tell when to
  automatically wakeup the process.

      def handle_call(request, _from, state) do
        state = do_stuff(state, request)
        timeout = TimeQueue.timeout(state.time_queue)
        {:reply, :ok, state, timeout}
      end

    By default, `timeout/1` and `timeout/2` (if called with an integer for the
    current time) will return `:infinity`  if the queue if empty. But you may
    pass `:hibernate` as the second argument for `timeout/2` or `timeout/3` to
    return `:hibernate` instead.

    Note that any other atom than `:infinity` or `:hibernate` will be returned
    as-is if as well if the queue is empty.
  """
  @spec timeout(t, :infinity | :hibernate | atom, now :: timestamp_ms) ::
          non_neg_integer | :infinity | :hibernate | atom

  def timeout(tq, if_empty, now) when is_atom(if_empty) and is_integer(now) do
    case peek(tq, now) do
      {:delay, _, timeout} -> min(timeout, @max_timeout)
      :empty -> if_empty
      {:ok, _value} -> 0
    end
  end

  @doc """
  Returns a stream of all the events in the queue.

  Note that this stream is immediate and does not wait for events.
  """
  @spec stream(t) :: Enumerable.t()
  def stream(%__MODULE__{tree: tree}) do
    Stream.unfold(:gb_trees.iterator(tree), fn iter ->
      case :gb_trees.next(iter) do
        {tref, val, iter} -> {event(tref, val), iter}
        :none -> nil
      end
    end)
  end

  @doc """
  Returns the queue as plain maps, lists and integers.

  The `Jason.Encoder` and `JSON.Encoder` implementations encode this
  representation. Use `dump/1` to encode the queue with another encoder, or to
  store it in a format that is independent from the internal data structure.
  `load/1` rebuilds the queue from it.

      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 2000, :world)
      iex> {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 1000, :hello)
      iex> %{s: 2, q: [first, second]} = TimeQueue.dump(tq)
      iex> first
      %{k: %{t: 1000, u: -2147483646}, v: :hello}
      iex> second
      %{k: %{t: 2000, u: -2147483647}, v: :world}

  The returned map has the following keys, shortened to a single letter to keep
  the encoded form small:

  * `:m` - The last unique integer given to a time reference. Time references
    created after a `load/1` continue from it.
  * `:s` - The number of events in the queue.
  * `:q` - The events, in the order they are due. Each event is a map with the
    time reference under `:k` and the value under `:v`. The time reference is a
    map with the scheduled timestamp in milliseconds under `:t` and the unique
    integer under `:u`.

  Values are returned as they were enqueued, so encoding the result as JSON
  requires values that the encoder supports.
  """
  @spec dump(t) :: dumped
  def dump(%__MODULE__{max_id: max_id, tree: tree}) do
    events = Enum.map(:gb_trees.to_list(tree), fn {tref, val} -> event(tref, val) end)
    %{m: max_id, s: :gb_trees.size(tree), q: events}
  end

  @doc """
  Rebuilds a queue from the data returned by `dump/1`.

  The keys can be atoms, as returned by `dump/1`, or strings, as returned by a
  JSON decoder. Queues persisted as plain maps by TimeQueue 1.x share this
  format and are loaded with this function too.

  Event values are loaded as they are given. A value that went through JSON
  comes back as the decoder returns it.

      iex> tq = TimeQueue.new()
      iex> {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 1000, :hello)
      iex> tq = tq |> TimeQueue.dump() |> TimeQueue.load()
      iex> TimeQueue.peek(tq, _now = 1000)
      {:ok, :hello}
  """
  @spec load(dumped | %{optional(binary) => term}) :: t
  def load(%{m: max_id, q: events}),
    do: load(max_id, events)

  def load(%{"m" => max_id, "q" => events}),
    do: load(max_id, events)

  defp load(max_id, events) when is_integer(max_id) do
    tree =
      events
      |> Enum.map(&load_event/1)
      |> :gb_trees.from_orddict()

    %__MODULE__{max_id: max_id, tree: tree}
  end

  defp load_event(%{k: tref, v: val}), do: {load_tref(tref), val}
  defp load_event(%{"k" => tref, "v" => val}), do: {load_tref(tref), val}

  defp load_tref(%{t: ts, u: id} = tref) when is_integer(ts) and is_integer(id), do: tref

  defp load_tref(%{"t" => ts, "u" => id}) when is_integer(ts) and is_integer(id),
    do: %{t: ts, u: id}

  defp event(tref, val),
    do: %{k: tref, v: val}

  @doc """
  This function is used internally to determine the current time when using
  functions `enqueue/3`, `pop/1`, `pop_event/1` and `peek_event/1`.

  It is a simple alias to `:erlang.system_time(:millisecond)`. TimeQueue does
  not use monotonic time since it already manages its own unique identifiers for
  queue entries.
  """
  @spec now :: integer
  def now,
    do: :erlang.system_time(:millisecond)

  @doc false
  def timespec_add(ttl, int),
    do: ttl_to_milliseconds(ttl) + int

  defp ttl_to_milliseconds({n, :ms}) when is_integer(n),
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
end
