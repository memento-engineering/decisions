## 0.4.0-dev.1

- Breaking: floors `grid_sdk` at `^0.4.0-dev.3` and `grid_assets` at `^0.7.0-dev.2` so lunar's
  the_grid dev.3-wave closure resolves override-free (dec-2di); the package now floors
  prereleases, so it moves onto the `dev` rung itself since pub refuses a stable package that
  depends on a prerelease. Migration: none for this package's own public API — it declares no
  call site against the grid_sdk 0.4.0-dev.1..dev.3 breaking surface (the deleted
  `projectBoard(linkBlockersByBeadId: ...)` argument and the genesis_tree re-export move) or the
  grid_assets 0.7.0-dev.2 breaking surface (the `armedSubstations` parameter and the deleted
  bead-prose dependency grammar); consumers pinning `grid_sdk: ^0.3.0-rc.11` or
  `grid_assets: ^0.7.0-dev.1` alongside this package must raise those floors themselves.

## 0.3.0

- Raise the `grid_assets` floor to `^0.7.0-dev.1` so lunar's closure resolves override-free (dec-eoa).

## 0.2.4 and earlier

Unreleased under this file; see git history for `grid_assets/decisions_grid_assets/pubspec.yaml`.
