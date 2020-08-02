defmodule TimeQueue.GbTreesTest do
  use ExUnit.Case
  alias TimeQueue.GbTrees, as: TQ
  doctest TimeQueue.GbTrees

  test "Basic API test on gb_trees" do
    assert tq = TQ.new()
    assert {:ok, {_, _} = tref, tq} = TQ.enqueue(tq, {500, :ms}, :myval)
    assert {:delay, ^tref, _delay} = TQ.peek(tq)
    assert {:delay, ^tref, delay} = TQ.pop(tq)

    Process.sleep(delay)

    # PEEK
    assert {:ok, entry} = TQ.peek(tq)
    assert :myval = TQ.value(entry)

    # POP
    assert {:ok, entry, tq} = TQ.pop(tq)
    assert :myval = TQ.value(entry)

    assert :empty = TQ.pop(tq)
  end

  defp insert_pop_many(iters) do
    tq = TQ.new()

    {insert_usec, tq} =
      :timer.tc(fn ->
        Enum.reduce(1..iters, tq, fn i, tq ->
          ts = :rand.uniform(10_000_000_000)
          {:ok, _, tq} = TQ.enqueue_abs(tq, ts, i)
          tq
        end)
      end)

    assert iters === TQ.size(tq)

    {pop_usec, final_val} =
      :timer.tc(fn ->
        unfold = fn
          {:ok, _, tq}, f -> f.(TQ.pop(tq), f)
          :empty, _f -> :ends_with_empty
          {:start, tq}, f -> f.(TQ.pop(tq), f)
        end

        unfold.({:start, tq}, unfold)
      end)

    assert :ends_with_empty === final_val

    IO.puts(
      "\n[tree] insert/pop #{pad_num(iters)} records (ms): #{fmt_usec(insert_usec)} #{
        fmt_usec(pop_usec)
      }"
    )
  end

  test "Inserting/popping many records with gb_trees implementation" do
    insert_pop_many(10)
    insert_pop_many(100)
    insert_pop_many(1000)
    insert_pop_many(10000)
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

  defp fmt_usec(usec) do
    usec
    |> div(1000)
    |> pad_num
  end

  defp pad_num(int) do
    int
    |> Integer.to_string()
    |> String.pad_leading(6, " ")
  end

  test "Timers are deletable" do
    tq = TQ.new()
    assert {:ok, tref, tq} = TQ.enqueue(tq, 0, :hello)
    assert {:ok, entry} = TQ.peek(tq)
    assert tref == TQ.tref(entry)
    # deleting an entry
    assert tq_del_entry = TQ.delete(tq, entry)
    assert 0 = TQ.size(tq_del_entry)
    # deleting an entry by tref
    assert tq_del_tref = TQ.delete(tq, tref)
    assert 0 = TQ.size(tq_del_tref)

    # deleting a tref that does not exist
    assert tq_del_bad_tref = TQ.delete(tq, {0, 0})
    assert 1 = TQ.size(tq_del_bad_tref)

    # deleting a an entry that was tampered deletes an entry with
    # same tref. Of course we tamper the value only.
    assert {:tqrec, ^tref, :hello} = entry
    bad_entry = {:tqrec, tref, :hola}
    assert tq_del_tamp_entry = TQ.delete(tq, bad_entry)
    assert 0 = TQ.size(tq_del_tamp_entry)
  end
end
