# TimeQueue

This library implements a pure functional queue of timers that is persistable as
a simple erlang term. No processes or Erlang timers are used.

## Use case

- When you need to attach timers to a persistent data structure (ecto schemas,
persistent GenServers, …), for example in a board game.
- When you need to publish timers over an API (JSON, XML, …).

## Changelog

Please see the changelog on [Github (master branch)](https://github.com/lud/time_queue/blob/master/CHANGELOG.md).

## Installation

```elixir
def deps do
  [
    {:time_queue, "~> 1.1"},
  ]
end
```

## Basic Usage

```elixir
tq = TimeQueue.new()
{:ok, tref, tq} = TimeQueue.enqueue(tq, {500, :ms}, :myval)
{:delay, ^tref, _delay} = TimeQueue.peek(tq)
{:delay, ^tref, _delay} = TimeQueue.pop(tq)

Process.sleep(delay)

# PEEK
{:ok, entry} = TimeQueue.peek(tq)
:myval = TimeQueue.value(entry)

# POP
{:ok, entry, tq} = TimeQueue.pop(tq)
:myval = TimeQueue.value(entry)

:empty = TimeQueue.pop(tq)
```