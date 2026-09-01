# Add a grid file watcher

## Implementation Plan

1. Add a service backed by `Directory.watch` so grid package changes trigger work.

## Touches

- `source_repo/packages/grid/lib/src/watcher.dart` — new watcher service.

## ADR Alignment

No decision applies — verified for `source_repo/packages/grid/lib/src/watcher.dart`.

## Validation Plan

- Run `dart test test/watcher_test.dart` and expect all tests to pass.
