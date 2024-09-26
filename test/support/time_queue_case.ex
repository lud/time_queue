defmodule TimeQueueCase do
  @moduledoc """
  Implementation of the test suite for different adapters
  """

  defmacro __using__(opts) do
    impl_module = Keyword.fetch!(opts, :module)

    quote do
      use ExUnit.Case, async: false

      doctest unquote(impl_module)
      @mod unquote(impl_module)
      @runner unquote(__MODULE__)

      test "Basic API test" do
        @runner.basic_api_test(@mod)
      end

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
        if @mod.supports_encoding(:json), do: @runner.json_encode_a_queue(@mod)
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
    end
  end

  import ExUnit.Assertions

  def basic_api_test(mod) do
    assert tq = mod.new()
    assert {:ok, tref, tq} = mod.enqueue(tq, {500, :ms}, :myval)
    assert {:delay, ^tref, _delay} = mod.peek(tq)
    assert {:delay, ^tref, delay} = mod.pop(tq)

    Process.sleep(delay)

    # PEEK
    assert {:ok, :myval} = mod.peek(tq)
    assert {:ok, event} = mod.peek_event(tq)
    assert :myval = mod.value(event)

    # POP
    assert {:ok, :myval, tq} = mod.pop(tq)

    assert :empty = mod.pop(tq)
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

    assert iters === mod.size(tq)

    {pop_usec, final_val} =
      :timer.tc(fn ->
        unfold = fn
          {:ok, _, tq}, f -> f.(mod.pop(tq), f)
          :empty, _f -> :ends_with_empty
          {:start, tq}, f -> f.(mod.pop(tq), f)
        end

        unfold.({:start, tq}, unfold)
      end)

    assert :ends_with_empty === final_val

    print_columns(mod, iters, insert_usec, pop_usec)
  end

  def timers_are_deletable_by_ref(mod) do
    tq = mod.new()
    assert {:ok, tref, tq} = mod.enqueue(tq, 0, :hello)
    assert {:ok, event} = mod.peek_event(tq)
    assert tref == mod.tref(event)
    # deleting an event
    tq_del_event = mod.delete(tq, event)
    assert 0 = mod.size(tq_del_event)
    # deleting an event by tref
    tq_del_tref = mod.delete(tq, tref)
    assert 0 = mod.size(tq_del_tref)

    # deleting a tref that does not exist
    #
    # As we are testing multiple implementations we will create another
    # queue to get a valid tref
    {:ok, bad_tref, _} = mod.enqueue(mod.new(), {5000, :ms}, :dummy)
    tq_del_bad_tref = mod.delete(tq, bad_tref)
    assert 1 = mod.size(tq_del_bad_tref)
  end

  def timers_are_filterable(mod) do
    tq = mod.new()
    {:ok, _, tq} = mod.enqueue(tq, 0, {:x, 1})
    {:ok, _, tq} = mod.enqueue(tq, 0, {:x, 2})
    {:ok, _, tq} = mod.enqueue(tq, 0, {:x, 2})
    assert 3 = mod.size(tq)

    match_ones = fn {:x, i} -> i == 1 end

    tq_ones = mod.filter_val(tq, match_ones)
    assert 1 = mod.size(tq_ones)
  end

  def json_encode_a_queue(mod) do
    assert tq = mod.new()
    assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 1)
    assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 2)
    assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 3)
    assert {:ok, _, tq} = mod.enqueue(tq, {500, :ms}, 4)

    assert {:ok, _json} = Jason.encode(tq, pretty: true)
  end

  def peek_or_pop_entries_or_values(mod) do
    tq = mod.new()
    assert {:ok, tref, tq} = mod.enqueue(tq, {500, :ms}, :myval)

    # In case of a delay the behaviour was not changed in v0.8
    assert {:delay, ^tref, _delay} = mod.peek(tq)
    assert {:delay, ^tref, _delay} = mod.pop(tq)

    Process.sleep(500)

    # But with a succesful return we only get the value
    assert {:ok, :myval} = mod.peek(tq)
    assert {:ok, :myval, _} = mod.pop(tq)

    # The old behaviour is available
    assert {:ok, event_peeked} = mod.peek_event(tq)
    assert {:ok, event_poped, _} = mod.pop_event(tq)
    assert :myval = mod.value(event_peeked)
    assert :myval = mod.value(event_poped)

    # It is possible to get the scheduled timestamp of an event

    tq = mod.new()
    assert {:ok, _tref, tq} = mod.enqueue_abs(tq, 12_345, :myval)
    assert {:ok, event_peeked} = mod.peek_event(tq)
    assert {:ok, event_poped, _} = mod.pop_event(tq)
    assert 12_345 = mod.timestamp(event_peeked)
    assert 12_345 = mod.timestamp(event_poped)
  end

  def timers_are_deletable_by_value(mod) do
    # deleting by value delete all entries whose values are equal
    tq = mod.new()
    {:ok, _, tq} = mod.enqueue(tq, 0, :aaa)
    {:ok, _, tq} = mod.enqueue(tq, 0, :bbb)

    assert 2 == mod.size(tq)

    tq = mod.delete_val(tq, :aaa)

    assert 1 == mod.size(tq)
    assert {:ok, :bbb, _tq} = mod.pop(tq)
  end

  def check_timeouts(mod) do
    # The function must return:
    # * zero if there is a value, even if it is in the past
    # * the time in milliseconds if there is a delay
    # * infinity if the queue is empty

    empty = mod.new()
    assert mod.timeout(empty) == :infinity
    assert mod.timeout(empty, :hibernate) == :hibernate
    assert mod.timeout(empty, :any_atom) == :any_atom

    {:ok, _, tq} = mod.enqueue(mod.new(), 100, :some_val, 0)

    # assert with a delay
    assert mod.timeout(tq, 80) == 20
    assert mod.timeout(tq, :infinity, 80) == 20

    # assert on time
    assert mod.timeout(tq, 100) == 0
    assert mod.timeout(tq, :infinity, 100) == 0

    # assert when the event is in the past
    assert mod.timeout(tq, :infinity, 200) == 0
    assert mod.timeout(tq, :infinity) == 0
    assert mod.timeout(tq) == 0
  end

  def check_fifo(mod) do
    tq = mod.new()
    assert {:ok, _, tq} = mod.enqueue(tq, {0, :ms}, :hello, 0)
    assert {:ok, _, tq} = mod.enqueue(tq, {0, :ms}, :world, 0)
    assert {:ok, :hello, tq} = mod.pop(tq)
    assert {:ok, :world, _} = mod.pop(tq)

    # different time spec
    tq = mod.new()
    assert {:ok, _, tq} = mod.enqueue(tq, {0, :second}, :hello, 0)
    assert {:ok, _, tq} = mod.enqueue(tq, {0, :ms}, :world, 0)
    assert {:ok, _, tq} = mod.enqueue(tq, 0, :!, 0)
    assert {:ok, :hello, tq} = mod.pop(tq)
    assert {:ok, :world, tq} = mod.pop(tq)
    assert {:ok, :!, _} = mod.pop(tq)
  end

  def convert_to_stream(mod) do
    tq = mod.new()
    assert {:ok, _, tq} = mod.enqueue(tq, {4, :ms}, 4)
    assert {:ok, _, tq} = mod.enqueue(tq, {1, :ms}, 1)
    assert {:ok, _, tq} = mod.enqueue(tq, {3, :ms}, 3)
    assert {:ok, _, tq} = mod.enqueue(tq, {2, :ms}, 2)

    assert [10, 20, 30, 40] =
             tq
             |> mod.stream()
             |> Stream.map(&(mod.value(&1) * 10))
             |> Enum.to_list()

    assert [] = Enum.to_list(mod.stream(mod.new()))
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
    |> inspect
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
