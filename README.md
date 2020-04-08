# TimeQueue

**TODO: Add description**

## Installation

```elixir
def deps do
  [
    {:time_queue, "~> 0.1.0"}
  ]
end
```

## Basic Usage

```elixir
tq = TimeQueue.new()
{:ok, tref, tq} = TimeQueue.enqueue(tq, {500, :ms}, :myval)
{:delay, delay} = TimeQueue.peek(tq)
{:delay, _delay} = TimeQueue.pop(tq)

Process.sleep(delay)

# PEEK
{:ok, entry} = TimeQueue.peek(tq)
:myval = TimeQueue.value(entry)

# POP
{:ok, entry, tq} = TimeQueue.pop(tq)
:myval = TimeQueue.value(entry)

:empty = TimeQueue.pop(tq)
```