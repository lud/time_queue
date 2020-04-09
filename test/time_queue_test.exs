defmodule TimeQueueTest do
  use ExUnit.Case
  doctest TimeQueue

  @iters 100_000

  test "Basic API test on gb_trees" do
    alias TimeQueue, as: TQ
    assert tq = TQ.new()
    assert {:ok, {_, _} = _tref, tq} = TQ.enqueue(tq, {500, :ms}, :myval)
    assert {:delay, delay} = TQ.peek(tq)
    assert {:delay, _delay} = TQ.pop(tq)

    Process.sleep(delay)

    # PEEK
    assert {:ok, entry} = TQ.peek(tq)
    assert :myval = TQ.value(entry)

    # POP
    assert {:ok, entry, tq} = TQ.pop(tq)
    assert :myval = TQ.value(entry)

    assert :empty = TQ.pop(tq)
  end

  test "Inserting/popping many records with gb_trees implementation" do
    alias TimeQueue, as: TQ
    IO.puts("TimeQueue gb_trees")

    tq = TQ.new()

    {usec, tq} =
      :timer.tc(fn ->
        Enum.reduce(1..@iters, tq, fn i, tq ->
          ts = :rand.uniform(10_000_000_000)
          {:ok, _, tq} = TQ.enqueue_abs(tq, ts, i)
          tq
        end)
      end)

    IO.puts("inserted #{@iters} records, took #{usec / 1000}ms")

    {usec, tq} =
      :timer.tc(fn ->
        unfold = fn
          {:ok, _, tq}, f -> f.(TQ.pop(tq), f)
          :empty, _f -> :ok
          {:start, tq}, f -> f.(TQ.pop(tq), f)
        end

        unfold.({:start, tq}, unfold)
      end)

    IO.puts("popped #{@iters} records, took #{usec / 1000}ms")
  end
end
