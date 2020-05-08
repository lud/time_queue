# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2020-05-08

### Changed

- The `peek` and `pop` functions will return the entry reference in case of a
  `:delay`.
  
  Previously:

      {:delay, delay} = TimeQueue.peek(tq)

  Now:

      {:delay, tref, delay} = TimeQueue.peek(tq)