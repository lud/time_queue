# TimeQueue

<!-- rdmx :badges
    hexpm         : "time_queue?color=4e2a8e"
    github_action : "lud/time_queue/elixir.yaml?label=CI&branch=main"
    license       : time_queue
    -->
[![hex.pm Version](https://img.shields.io/hexpm/v/time_queue?color=4e2a8e)](https://hex.pm/packages/time_queue)
[![Build Status](https://img.shields.io/github/actions/workflow/status/lud/time_queue/elixir.yaml?label=CI&branch=main)](https://github.com/lud/time_queue/actions/workflows/elixir.yaml?query=branch%3Amain)
[![License](https://img.shields.io/hexpm/l/time_queue.svg)](https://hex.pm/packages/time_queue)
<!-- rdmx /:badges -->

This library implements a pure functional queue of timers that is persistable as
a simple erlang term. No processes or Erlang timers are used.

## Use case

- When you need to attach timers to a persistent data structure (ecto schemas,
persistent GenServers, …), for example in a board game.
- When you need to publish timers over an API (JSON, XML, …).

## Changelog

Please see the changelog on [Github (master branch)](https://github.com/lud/time_queue/blob/master/CHANGELOG.md).

## Installation

<!-- rdmx :app_dep vsn:$app_vsn -->
```elixir
defp deps do
  [
    {:time_queue, "~> 1.2"},
  ]
end
```
<!-- rdmx /:app_dep -->

## Basic Usage

<!-- rdmx :section name:"basic usage" format:true -->
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
<!-- rdmx /:section -->