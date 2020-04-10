defmodule TimeQueueTest do
  use ExUnit.Case
  alias TimeQueue, as: TQ
  doctest TimeQueue

  @iters 100_000

  test "Basic API test on gb_trees" do
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
    IO.puts("TimeQueue gb_trees")

    tq = TQ.new()

    {usec, _tq} =
      :timer.tc(fn ->
        Enum.reduce(1..@iters, tq, fn i, tq ->
          ts = :rand.uniform(10_000_000_000)
          {:ok, _, tq} = TQ.enqueue_abs(tq, ts, i)
          tq
        end)
      end)

    IO.puts("inserted #{@iters} records, took #{usec / 1000}ms")

    {usec, _tq} =
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

  test "Timers are deletable" do
    tq = TQ.new()
    assert {:ok, tref, tq} = TQ.enqueue(tq, 0, :hello)
    assert {:ok, entry} = TQ.peek(tq)
    assert tref == TQ.tref(entry)
    # deleting an entry
    assert {:ok, tq_del_entry} = TQ.delete(tq, entry)
    assert 0 = TQ.size(tq_del_entry)
    # deleting an entry by tref
    assert {:ok, tq_del_tref} = TQ.delete(tq, tref)
    assert 0 = TQ.size(tq_del_tref)

    # deleting a tref that does not exist
    assert {:ok, tq_del_bad_tref} = TQ.delete(tq, {0, 0})
    assert 1 = TQ.size(tq_del_bad_tref)

    # deleting a an entry that was tampered deletes an entry with 
    # same tref. Of course we tamper the value only.
    assert {:tqrec, ^tref, :hello} = entry
    bad_entry = {:tqrec, tref, :hola}
    assert {:ok, tq_del_tamp_entry} = TQ.delete(tq, bad_entry)
    assert 0 = TQ.size(tq_del_tamp_entry)
  end
end
