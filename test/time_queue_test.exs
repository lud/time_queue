defmodule TimeQueueTest do
  use TimeQueueCase, module: TimeQueue

  defp sample_queue do
    tq = TimeQueue.new()
    {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 200, :b)
    {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 100, :a)
    {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 200, :c)
    {:ok, :a, tq} = TimeQueue.pop(tq, 100)
    tq
  end

  # Same data as the list-based TimeQueue 1.x produced for sample_queue/0.
  @legacy_map %{
    m: -2_147_483_645,
    s: 2,
    q: [
      %{k: %{t: 200, u: -2_147_483_647}, v: :b},
      %{k: %{t: 200, u: -2_147_483_645}, v: :c}
    ]
  }

  test "dump returns the 1.x data format" do
    assert @legacy_map == TimeQueue.dump(sample_queue())
  end

  test "load reads a 1.x queue" do
    tq = TimeQueue.load(@legacy_map)

    assert 2 == TimeQueue.size(tq)
    assert {:ok, _, tq} = TimeQueue.enqueue_abs(tq, 150, :d)
    assert {:ok, :d, tq} = TimeQueue.pop(tq, 200)
    assert {:ok, :b, tq} = TimeQueue.pop(tq, 200)
    assert {:ok, :c, tq} = TimeQueue.pop(tq, 200)
    assert :empty = TimeQueue.pop(tq, 200)
  end

  test "load is the inverse of dump" do
    dumped = TimeQueue.dump(sample_queue())
    assert dumped == dumped |> TimeQueue.load() |> TimeQueue.dump()
  end

  test "load reads a queue decoded from JSON with string keys" do
    tq = sample_queue() |> Jason.encode!() |> Jason.decode!() |> TimeQueue.load()

    assert 2 == TimeQueue.size(tq)
    assert {:ok, tref, tq} = TimeQueue.enqueue_abs(tq, 150, "d")
    assert %{t: 150, u: -2_147_483_644} = tref
    assert {:ok, "d", tq} = TimeQueue.pop(tq, 200)
    assert {:ok, "b", tq} = TimeQueue.pop(tq, 200)
    assert {:ok, "c", tq} = TimeQueue.pop(tq, 200)
    assert :empty = TimeQueue.pop(tq, 200)
  end

  test "load rejects malformed time references" do
    assert_raise FunctionClauseError, fn ->
      TimeQueue.load(%{m: 1, q: [%{k: %{t: "1", u: 1}, v: :a}]})
    end
  end

  test "Jason and JSON encode the dumped queue" do
    tq = sample_queue()
    expected = @legacy_map |> Jason.encode!() |> Jason.decode!()

    assert expected == tq |> Jason.encode!() |> Jason.decode!()

    if Code.ensure_loaded?(JSON) do
      assert expected == tq |> JSON.encode!() |> JSON.decode!()
    end
  end
end
