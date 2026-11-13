defmodule TimeQueueCase do
  @moduledoc """
  Implementation of the test suite for different adapters
  """

  defmacro __using__(opts) do
    impl_module =
      opts
      |> Keyword.fetch!(:module)
      |> Macro.expand_literals(__CALLER__)

    quote do
      use ExUnit.Case, async: true

      doctest unquote(impl_module)
      @mod unquote(impl_module)

      @runner unquote(__MODULE__)

      test "Basic API test" do
        @runner.basic_api_test(@mod)
      end

      @tag :benchmark
      test "Inserting/popping many records with #{@mod} implementation" do
        IO.puts("Running many iterations with #{@mod}")
        IO.write("\n")
        @runner.print_columns("Module", "Items", "Insert ms", "Pop ms")
        @runner.insert_pop_many(@mod, 10)
        @runner.insert_pop_many(@mod, 100)
        @runner.insert_pop_many(@mod, 1000)
        @runner.insert_pop_many(@mod, 10_000)
      end

      # Some bad test to check that performance is not degrading
      # test "Inserting/popping many records in multiple queues concurrently" do
      #   concur = 4 * System.schedulers_online()

      #   for _ <- 1..concur do
      #     &insert_pop_many/0
      #   end
      #   |> Enum.map(&Task.async/1)
      #   |> Enum.map(&Task.await(&1, :infinity))

      #   # |> Task.async_stream(fn f -> f.() end)
      #   # |> Stream.run()
      # end

      test "Timers are deletable by ref" do
        @runner.timers_are_deletable_by_ref(@mod)
      end

      test "Timers are filterable" do
        @runner.timers_are_filterable(@mod)
      end

      test "Timers are deletable by value" do
        @runner.timers_are_deletable_by_value(@mod)
      end

      test "json encode a queue" do
        @runner.json_encode_a_queue(@mod)
      end

      test "peek/pop entries or values" do
        @runner.peek_or_pop_entries_or_values(@mod)
      end

      test "return a gen_server compatible timeout" do
        @runner.check_timeouts(@mod)
      end

      test "enqueue with same time is FIFO" do
        @runner.check_fifo(@mod)
      end

      test "stream" do
        @runner.convert_to_stream(@mod)
      end

      test "negative TTLs schedule events in the past" do
        @runner.check_negative_ttls(@mod)
      end

      test "now/0 returns the system time" do
        @runner.check_now(@mod)
      end

      test "enqueue/3 schedules from the system time" do
        @runner.check_enqueue_uses_system_time(@mod)
      end

      test "peek, pop and timeout default to the system time" do
        @runner.check_reads_use_system_time(@mod)
      end
    end
  end

  import ExUnit.Assertions

  # This does not work. So we need to put a `_ = ` before all `assert` calls.
  @dialyzer [:unmatched_returns]

  def basic_api_test(mod) do
    tq = mod.new()
    _ = assert {:ok, tref, tq} = mod.enqueue(tq, {500, :ms}, :myval, 0)
    _ = assert {:delay, ^tref, 500} = mod.peek(tq, 0)
    _ = assert {:delay, ^tref, 1} = mod.pop(tq, 499)

    # PEEK
    _ = assert {:ok, :myval} = mod.peek(tq, 500)
    _ = assert {:ok, event} = mod.peek_event(tq, 500)
    _ = assert :myval = mod.value(event)

    # POP
    _ = assert {:ok, :myval, tq} = mod.pop(tq, 500)

    _ = assert :empty = mod.pop(tq, 500)
  end

  def insert_pop_many(mod, iters) do
    tq = mod.new()

    {insert_usec, tq} =
      :timer.tc(fn ->
        Enum.reduce(1..iters, tq, fn i, tq ->
          ts = :rand.uniform(10_000_000_000)
          {:ok, _, tq} = mod.enqueue_abs(tq, ts, i)
          tq
        end)
      end)

    _ = assert iters === mod.size(tq)

    {pop_usec, final_val} =
      :timer.tc(fn ->
        unfold = fn
          {:ok, _, tq}, f -> f.(mod.pop(tq), f)
          :empty, _f -> :ends_with_empty
          {:start, tq}, f -> f.(mod.pop(tq), f)
        end

        unfold.({:start, tq}, unfold)
      end)

    _ = assert :ends_with_empty === final_val

    print_columns(mod, iters, insert_usec, pop_usec)
  end

  def timers_are_deletable_by_ref(mod) do
    tq = mod.new()
    _ = assert {:ok, tref, tq} = mod.enqueue(tq, 0, :hello)
    _ = assert {:ok, event} = mod.peek_event(tq)
    _ = assert tref == mod.tref(event)
    # deleting an event
    tq_del_event = mod.delete(tq, event)
    _ = assert 0 = mod.size(tq_del_event)
    # deleting an event by tref
    tq_del_tref = mod.delete(tq, tref)
    _ = assert 0 = mod.size(tq_del_tref)

    # deleting a tref that does not exist
    #
    # As we are testing multiple implementations we will create another
    # queue to get a valid tref
    {:ok, bad_tref, _} = mod.enqueue(mod.new(), {5000, :ms}, :dummy)
    tq_del_bad_tref = mod.delete(tq, bad_tref)
    _ = assert 1 = mod.size(tq_del_bad_tref)
  end

  def timers_are_filterable(mod) do
    tq = mod.new()
    {:ok, _, tq} = mod.enqueue(tq, 0, {:x, 1})
    {:ok, _, tq} = mod.enqueue(tq, 0, {:x, 2})
    {:ok, _, tq} = mod.enqueue(tq, 0, {:x, 2})
    _ = assert 3 = mod.size(tq)

    match_ones = fn {:x, i} -> i == 1 end

    tq_ones = mod.filter_val(tq, match_ones)
    _ = assert 1 = mod.size(tq_ones)

    tq_ones = mod.filter(tq, fn event -> match_ones.(mod.value(event)) end)
    _ = assert 1 = mod.size(tq_ones)
    _ = assert {:ok, {:x, 1}, _} = mod.pop(tq_ones)

    {:ok, tref, tq} = mod.enqueue(tq, 0, {:x, 3})
    tq_tref = mod.filter(tq, fn event -> mod.tref(event) == tref end)
    _ = assert 1 = mod.size(tq_tref)
    _ = assert {:ok, {:x, 3}, _} = mod.pop(tq_tref)
  end

  def json_encode_a_queue(mod) do
    tq = mod.new()
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 1)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 2)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 3)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 4)

    _ = assert {:ok, _json} = Jason.encode(tq, pretty: true)
  end

  def peek_or_pop_entries_or_values(mod) do
    tq = mod.new()
    _ = assert {:ok, tref, tq} = mod.enqueue(tq, {500, :ms}, :myval, 0)

    # In case of a delay the behaviour was not changed in v0.8
    _ = assert {:delay, ^tref, 500} = mod.peek(tq, 0)
    _ = assert {:delay, ^tref, 500} = mod.pop(tq, 0)
    _ = assert {:delay, ^tref, 500} = mod.peek_event(tq, 0)
    _ = assert {:delay, ^tref, 500} = mod.pop_event(tq, 0)

    # But with a succesful return we only get the value
    _ = assert {:ok, :myval} = mod.peek(tq, 500)
    _ = assert {:ok, :myval, _} = mod.pop(tq, 500)

    # The old behaviour is available
    _ = assert {:ok, event_peeked} = mod.peek_event(tq, 500)
    _ = assert {:ok, event_poped, _} = mod.pop_event(tq, 500)
    _ = assert :myval = mod.value(event_peeked)
    _ = assert :myval = mod.value(event_poped)

    # It is possible to get the scheduled timestamp of an event

    tq = mod.new()
    _ = assert {:ok, _tref, tq} = mod.enqueue_abs(tq, 12_345, :myval)
    _ = assert {:ok, event_peeked} = mod.peek_event(tq)
    _ = assert {:ok, event_poped, _} = mod.pop_event(tq)
    _ = assert 12_345 = mod.timestamp(event_peeked)
    _ = assert 12_345 = mod.timestamp(event_poped)
  end

  def timers_are_deletable_by_value(mod) do
    # deleting by value delete all entries whose values are equal
    tq = mod.new()
    {:ok, _, tq} = mod.enqueue(tq, 0, :aaa)
    {:ok, _, tq} = mod.enqueue(tq, 0, :bbb)

    _ = assert 2 == mod.size(tq)

    tq = mod.delete_val(tq, :aaa)

    _ = assert 1 == mod.size(tq)
    _ = assert {:ok, :bbb, _tq} = mod.pop(tq)
  end

  def check_timeouts(mod) do
    # The function must return:
    # * zero if there is a value, even if it is in the past
    # * the time in milliseconds if there is a delay
    # * infinity if the queue is empty

    empty = mod.new()
    _ = assert mod.timeout(empty) == :infinity
    _ = assert mod.timeout(empty, :hibernate) == :hibernate
    _ = assert mod.timeout(empty, :any_atom) == :any_atom

    {:ok, _, tq} = mod.enqueue(mod.new(), 100, :some_val, 0)

    # assert with a delay
    _ = assert mod.timeout(tq, 80) == 20
    _ = assert mod.timeout(tq, :infinity, 80) == 20

    # assert on time
    _ = assert mod.timeout(tq, 100) == 0
    _ = assert mod.timeout(tq, :infinity, 100) == 0

    # assert when the event is in the past
    _ = assert mod.timeout(tq, :infinity, 200) == 0
    _ = assert mod.timeout(tq, :infinity) == 0
    _ = assert mod.timeout(tq) == 0

    # the delay is capped to the largest timeout accepted by receive
    max_timeout = 4_294_967_295
    {:ok, _, tq} = mod.enqueue(mod.new(), max_timeout, :some_val, 0)
    _ = assert mod.timeout(tq, 0) == max_timeout
    _ = assert mod.timeout(tq, 1) == max_timeout - 1

    {:ok, _, tq} = mod.enqueue(mod.new(), max_timeout + 1, :some_val, 0)
    _ = assert mod.timeout(tq, 0) == max_timeout
    _ = assert mod.timeout(tq, :hibernate, 0) == max_timeout
    _ = assert {:delay, _, delay} = mod.pop(tq, 0)
    _ = assert delay == max_timeout + 1

    {:ok, _, tq} = mod.enqueue(mod.new(), {60, :days}, :some_val, 0)
    _ = assert mod.timeout(tq, 0) == max_timeout
  end

  def check_fifo(mod) do
    tq = mod.new()
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {0, :ms}, :hello, 0)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {0, :ms}, :world, 0)
    _ = assert {:ok, :hello, tq} = mod.pop(tq)
    _ = assert {:ok, :world, _} = mod.pop(tq)

    # different time spec
    tq = mod.new()
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {0, :second}, :hello, 0)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {0, :ms}, :world, 0)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, 0, :!, 0)
    _ = assert {:ok, :hello, tq} = mod.pop(tq)
    _ = assert {:ok, :world, tq} = mod.pop(tq)
    _ = assert {:ok, :!, _} = mod.pop(tq)
  end

  def convert_to_stream(mod) do
    tq = mod.new()
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {4, :ms}, 4, 0)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {1, :ms}, 1, 0)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {3, :ms}, 3, 0)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {2, :ms}, 2, 0)

    _ =
      assert [10, 20, 30, 40] =
               tq
               |> mod.stream()
               |> Stream.map(&(mod.value(&1) * 10))
               |> Enum.to_list()

    _ = assert [] = Enum.to_list(mod.stream(mod.new()))
  end

  def check_negative_ttls(mod) do
    now = 1_000_000_000

    ttls = [
      {-1, :ms},
      {-1, :second},
      {-1, :seconds},
      {-1, :minute},
      {-1, :minutes},
      {-1, :hour},
      {-1, :hours},
      {-1, :day},
      {-1, :days},
      {-1, :week},
      {-1, :weeks},
      -1
    ]

    for ttl <- ttls do
      _ = assert {:ok, _, tq} = mod.enqueue(mod.new(), ttl, :late, now)
      _ = assert 0 == mod.timeout(tq, now)
      _ = assert {:ok, event} = mod.peek_event(tq, now)
      _ = assert mod.timestamp(event) < now
      _ = assert {:ok, :late, _} = mod.pop(tq, now)
    end

    tq = mod.new()
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {10, :ms}, :future, now)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, 0, :now, now)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {-1, :second}, :due_1s_ago, now)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, {-5, :ms}, :due_5ms_ago, now)
    _ = assert {:ok, _, tq} = mod.enqueue(tq, -60_000, :due_1m_ago, now)

    _ = assert {:ok, :due_1m_ago, tq} = mod.pop(tq, now)
    _ = assert {:ok, :due_1s_ago, tq} = mod.pop(tq, now)
    _ = assert {:ok, :due_5ms_ago, tq} = mod.pop(tq, now)
    _ = assert {:ok, :now, tq} = mod.pop(tq, now)
    _ = assert {:delay, _, 10} = mod.pop(tq, now)
  end

  @hour 3_600_000
  @clock_margin 60_000

  def check_now(mod) do
    before = System.system_time(:millisecond)
    now = mod.now()
    _ = assert now in before..System.system_time(:millisecond)
  end

  def check_enqueue_uses_system_time(mod) do
    for {ttl, ms} <- [{@hour, @hour}, {{1, :hour}, @hour}, {0, 0}, {{-1, :hour}, -@hour}] do
      before = System.system_time(:millisecond)
      _ = assert {:ok, _, tq} = mod.enqueue(mod.new(), ttl, :val)
      later = System.system_time(:millisecond)

      _ = assert {:ok, event} = mod.peek_event(tq, later + ms)
      _ = assert mod.timestamp(event) in (before + ms)..(later + ms)
    end
  end

  def check_reads_use_system_time(mod) do
    _ =
      assert {:ok, tref, future} =
               mod.enqueue_abs(mod.new(), System.system_time(:millisecond) + @hour, :future)

    _ = assert {:delay, ^tref, delay} = mod.peek(future)
    _ = assert delay in (@hour - @clock_margin)..@hour
    _ = assert {:delay, ^tref, delay} = mod.peek_event(future)
    _ = assert delay in (@hour - @clock_margin)..@hour
    _ = assert {:delay, ^tref, delay} = mod.pop(future)
    _ = assert delay in (@hour - @clock_margin)..@hour
    _ = assert {:delay, ^tref, delay} = mod.pop_event(future)
    _ = assert delay in (@hour - @clock_margin)..@hour
    _ = assert mod.timeout(future) in (@hour - @clock_margin)..@hour
    _ = assert mod.timeout(future, :hibernate) in (@hour - @clock_margin)..@hour

    _ =
      assert {:ok, tref, past} =
               mod.enqueue_abs(mod.new(), System.system_time(:millisecond) - 1000, :past)

    _ = assert {:ok, :past} = mod.peek(past)
    _ = assert {:ok, event} = mod.peek_event(past)
    _ = assert tref == mod.tref(event)
    _ = assert {:ok, :past, _} = mod.pop(past)
    _ = assert {:ok, event, _} = mod.pop_event(past)
    _ = assert tref == mod.tref(event)
    _ = assert 0 == mod.timeout(past)
    _ = assert 0 == mod.timeout(past, :hibernate)
  end

  def print_columns(mod, iters, insert_usec, pop_usec) do
    IO.puts([
      pad_mod(mod),
      pad_num(iters),
      fmt_usec(insert_usec),
      fmt_usec(pop_usec)
    ])
  end

  @col_pad 12

  def fmt_usec(usec) when is_integer(usec) do
    usec
    |> div(1000)
    |> pad_num()
  end

  def fmt_usec(title), do: pad_col(title)

  defp pad_num(int) when is_integer(int) do
    int
    |> Integer.to_string()
    |> pad_col()
  end

  defp pad_num(title), do: pad_col(title)

  defp pad_mod(module) when is_atom(module) do
    module
    |> inspect()
    |> String.split(".")
    |> :lists.last()
    |> pad_col()
  end

  defp pad_mod(text) when is_binary(text),
    do: pad_col(text)

  defp pad_col(text) when is_binary(text) do
    String.pad_trailing(text, @col_pad, " ")
  end
end
