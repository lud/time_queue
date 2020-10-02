defmodule TimeQueueCase do
  use ExUnit.CaseTemplate

  defmacro __using__(opts) do
    impl = Keyword.fetch!(opts, :impl)

    quote location: :keep do
      use ExUnit.Case, async: false
      alias unquote(impl), as: TQ
      doctest unquote(impl)

      test "Basic API test" do
        assert tq = TQ.new()
        assert {:ok, tref, tq} = TQ.enqueue(tq, {500, :ms}, :myval)
        assert {:delay, ^tref, _delay} = TQ.peek(tq)
        assert {:delay, ^tref, delay} = TQ.pop(tq)

        Process.sleep(delay)

        # PEEK
        assert {:ok, :myval} = TQ.peek(tq)
        assert {:ok, entry} = TQ.peek_entry(tq)
        assert :myval = TQ.value(entry)

        # POP
        assert {:ok, :myval, tq} = TQ.pop(tq)

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
          "\n[#{inspect(unquote(impl))}] insert/pop #{pad_num(iters)} records (ms): #{
            fmt_usec(insert_usec)
          } #{fmt_usec(pop_usec)}"
        )
      end

      test "Inserting/popping many records with maps implementation" do
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

      test "Timers are deletable by ref" do
        tq = TQ.new()
        assert {:ok, tref, tq} = TQ.enqueue(tq, 0, :hello)
        assert {:ok, entry} = TQ.peek_entry(tq)
        assert tref == TQ.tref(entry)
        # deleting an entry
        tq_del_entry = TQ.delete(tq, entry)
        assert 0 = TQ.size(tq_del_entry)
        # deleting an entry by tref
        tq_del_tref = TQ.delete(tq, tref)
        assert 0 = TQ.size(tq_del_tref)

        # deleting a tref that does not exist 
        # 
        # As we are testing multiple implementations we will create another
        # queue to get a valid tref
        {:ok, bad_tref, _} = TQ.enqueue(TQ.new(), {5000, :ms}, :dummy)
        tq_del_bad_tref = TQ.delete(tq, bad_tref)
        assert 1 = TQ.size(tq_del_bad_tref)
      end

      test "Timers are filterable" do
        tq = TQ.new()
        {:ok, _, tq} = TQ.enqueue(tq, 0, {:x, 1})
        {:ok, _, tq} = TQ.enqueue(tq, 0, {:x, 2})
        {:ok, _, tq} = TQ.enqueue(tq, 0, {:x, 2})
        assert 3 = TQ.size(tq)

        match_ones = fn {:x, i} -> i == 1 end

        tq_ones = TQ.filter_val(tq, match_ones)
        assert 1 = TQ.size(tq_ones)
      end

      # test "Timers are deletable by value" do
      #   # deleting by value delete all entries whose values are equal
      #   tq = TQ.new()
      #   {:ok, _, tq} = TQ.enqueue(tq, 0, :aaa)
      #   {:ok, _, tq} = TQ.enqueue(tq, 0, :bbb)

      #   assert 2 = TQ.size(tq)

      #   tq_no_vs =
      #     TQ.delete_val(tq, :aaa)
      #     |> IO.inspect(label: "tq_no_vs")

      #   assert 1 = TQ.size(tq)
      #   assert {:ok, last} = TQ.pop(tq)
      #   assert :bbb = TQ.value(last)
      # end

      test "json encode a queue" do
        if TQ.supports_encoding(:json) do
          assert tq = TQ.new()
          assert {:ok, _, tq} = TQ.enqueue(tq, {500, :ms}, 1)
          assert {:ok, _, tq} = TQ.enqueue(tq, {500, :ms}, 2)
          assert {:ok, _, tq} = TQ.enqueue(tq, {500, :ms}, 3)
          assert {:ok, _, tq} = TQ.enqueue(tq, {500, :ms}, 4)

          assert {:ok, json} = Jason.encode(tq, pretty: true)
        end
      end

      test "peek/pop entries or values" do
        tq = TQ.new()
        assert {:ok, tref, tq} = TQ.enqueue(tq, {500, :ms}, :myval)

        # # In case of a delay the behaviour was not changed in v0.8
        assert {:delay, ^tref, _delay} = TQ.peek(tq)
        assert {:delay, ^tref, delay} = TQ.pop(tq)

        Process.sleep(500)

        # # But with a succesful return we only get the value
        assert {:ok, :myval} = TQ.peek(tq)
        assert {:ok, :myval, _} = TQ.pop(tq)

        # # The old behaviour is available
        assert {:ok, entry_peeked} = TQ.peek_entry(tq)
        assert {:ok, entry_poped, _} = TQ.pop_entry(tq)
        assert :myval = TQ.value(entry_peeked)
        assert :myval = TQ.value(entry_poped)
      end
    end
  end
end
