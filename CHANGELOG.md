# Changelog

All notable changes to this project will be documented in this file.

## [2.0.0] - 2026-11-13

This release has two breaking changes: the queue is now backed by `gb_trees`, and `timeout/1,2,3` is capped at the largest timeout the BEAM accepts.

**New backend.** A queue is now an opaque `%TimeQueue{}` struct holding a `gb_trees` tree, where it used to be a plain map holding a sorted list. Inserts, pops and deletes by time reference are O(log n).

- Queues persisted by 1.x, for instance with `:erlang.term_to_binary/1`, are loaded with the new `TimeQueue.load/1`. It reads the 1.x map with atom keys, and with string keys when it comes from a JSON decoder.
- `TimeQueue.dump/1` returns the queue as the same `%{m: _, s: _, q: _}` map as 1.x, for storage or for any encoder.
- The JSON output is unchanged. It now goes through the `Jason.Encoder` and `JSON.Encoder` protocols, and `jason` is an optional dependency.
- Code that pattern matches on the queue map, or compares two queues with `==`, must use the `TimeQueue` functions or compare the results of `dump/1`.
- `TimeQueue.GbTrees` is removed, since `TimeQueue` now is that implementation. `supports_encoding/1` is removed too.

**Timeout cap.** `TimeQueue.timeout/1,2,3` returns at most `4_294_967_295` milliseconds (about 49.7 days), the limit for `receive` and `GenServer` timeouts. An event scheduled further away used to crash the process with `:timeout_value`.

When the next event is beyond that limit, the process wakes up before the event is due. `pop/1` then returns `{:delay, tref, ms}` with the full remaining delay, and `timeout/1` gives the next wait. Code that passes the timeout to `Process.send_after/3` or `:timer.send_after/2`, which accept larger values, must handle that `{:delay, tref, ms}` return.


### 🚀 Features

- [**breaking**] Back TimeQueue with gb_trees and encode it through protocols (#98)

### 🐛 Bug Fixes

- *(gb_trees)* Pass events to the filter/2 callback (#95)
- Accept negative TTLs for all timespec units (#97)
- [**breaking**] Cap timeout/3 at the maximum receive timeout – by lud-wj
- Format negative intervals in TimeInterval.to_string/1,2 – by lud-wj

### 📚 Documentation

- Fix README example, changelog links and misplaced specs (#96)

### 🧪 Testing

- Fix race condition in tests – by lud-wj
- Stop depending on real time in the test suite – by lud-wj

### ⚙️ Miscellaneous Tasks

- Limit justfile verbosity on mix.deps – by lud-wj

## [1.2.3] - 2026-05-29

### ⚙️ Miscellaneous Tasks

- Fixed Compilation warnings for Elixir 1.20 – by lud-wj

## [1.2.2] - 2025-11-23

### ⚙️ Miscellaneous Tasks

- Maintenance release – by lud-wj

## [1.2.1] - 2025-05-13

### ⚙️ Miscellaneous Tasks

- Update dependabot config (#5)
- Update CI config (#6)
- Refactor time-interval formatting – by lud-wj
- Suppress dialyzer warnings – by lud-wj
- Update dependabot config (#11)
- Update Elixir Github workflow (#19)

## [1.2.0] - 2024-09-26

### 🚀 Features

- Added stream/1 function – by lud-wj

### ⚙️ Miscellaneous Tasks

- Update version in readme – by lud-wj
- Upgrade dependencies – by lud-wj

## [1.1.1] - 2023-11-22

### 🚀 Features

- Added the timestamp/1 function that returns the absolute time of an event – by lud-wj

## [1.1.0] - 2023-11-22

### ⚙️ Miscellaneous Tasks

- Removed deprecated pop_entry and peek_entry – by lud-wj
- Use mix_version for versioning – by lud-wj

## [0.6.0] - 2020-08-02

