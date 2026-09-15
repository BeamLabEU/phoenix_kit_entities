# PR #48 follow-up

How each finding in `GROK_REVIEW.md` and `CODEX_REVIEW.md` was resolved.

## Fixed (Batch 1 — 2026-09-15, folded into commit bdcb389 before pushing)

- ~~Codex 4 — the concurrency test could pass on the old shared-map code by
  scheduling luck, and it left forty guard registrations behind.~~ All forty
  tasks now wait until every one exists and are then released together, and the
  test erases its registrations on exit. On the old code it failed five runs out
  of five.

## Skipped (with rationale)

- **Codex 2 — a node hot-upgraded onto this code without restarting would miss
  guards registered under the old map key until they re-register.** Deploys
  restart the application, and Phoenix's code reloader reloads the host app's own
  modules, not this dependency. Owners re-register at every boot.
- **Grok** — no findings: the per-owner keys remove the race, same-owner
  re-registration keeps replace semantics, and the new layout avoids the global
  GC the shared map paid on every registration. It also explained why the first
  attempt's `:global.trans` lock timed out under contention.
- **Codex 1 and 3** — reported sound.

## Files touched

| File | Change |
|------|--------|
| `lib/phoenix_kit_entities/managed.ex` | one `:persistent_term` key per owner |
| `test/phoenix_kit_entities/managed_test.exs` | concurrent registration test |

## Verification

- Full suite 1264 tests, 0 failures; `mix precommit` clean.
- New test: fails on the old code 5/5, passes 3/3.
- max-dev after deploy and restart: both catalogue guards registered.

## Open

None.
