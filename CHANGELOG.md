# CHANGELOG

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/) and [Keep a Changelog](http://keepachangelog.com/).



## Unreleased
---

### New

### Changes

### Fixes

### Breaks


## 0.8.0 - (2020-10-02)
---

### Breaks
* the `peek` and `pop` functions will now only return the value instead of the full entry for the `{:ok, …}` return types. The functions `peek_entry` and `pop_entry` are available to get the full entry.


## 0.7.0 - (2020-09-12)
---

### New
* It is now possible to filter the queue with a filter function, and delete all
  entries whose value match a given value. This operation is slow on the
  gb_trees implementation as the tree has to be converted to a list temporarily.


## 0.5.0 - (2020-05-08)

### Changes

* The `peek` and `pop` functions will return the entry reference in case of a
  `:delay`.
  
  Previously:

      {:delay, delay} = TimeQueue.peek(tq)

  Now:

      {:delay, tref, delay} = TimeQueue.peek(tq)
---

