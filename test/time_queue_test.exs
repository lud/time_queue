defmodule TimeQueueTest do
  use ExUnit.Case
  doctest TimeQueue

  test "Basic API test" do
    assert [] = tq = TimeQueue.new()
    assert {:ok, {_, _} = _tref, tq} = TimeQueue.enqueue(tq, {500, :ms}, :myval)
    assert {:delay, delay} = TimeQueue.peek(tq)
    assert {:delay, _delay} = TimeQueue.pop(tq)

    Process.sleep(delay)

    # PEEK
    assert {:ok, entry} = TimeQueue.peek(tq)
    assert :myval = TimeQueue.value(entry)

    # POP
    assert {:ok, entry, tq} = TimeQueue.pop(tq)
    assert :myval = TimeQueue.value(entry)

    assert :empty = TimeQueue.pop(tq)
  end
end
