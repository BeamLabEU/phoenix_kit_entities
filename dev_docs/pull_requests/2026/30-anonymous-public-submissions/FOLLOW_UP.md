# PR #30 follow-up — Store anonymous public submissions with no creator

Triaged 2026-08-28 as part of the four-repo quality sweep. The review approved
the PR, fixed its one finding at review time, and recorded three pre-existing
failures it deliberately did not touch. All re-verified against current code.

## Fixed (pre-existing)

- ~~**BUG - LOW:** the PR failed this repo's gate — `mix precommit` exited 2
  with 7 credo `--strict` "Nested modules could be aliased" findings across
  four test modules.~~ Fixed on main at review time. `mix precommit` is clean
  today.
- ~~The 28 committed JSON test droppings in `priv/entities/`, swept in by a
  `git add -A` and published to Hex into the very directory
  `Storage.default_path/0` reads back.~~ Directory is empty and
  `/priv/entities/` is gitignored (`.gitignore:28`), with the reason recorded
  beside it.

## Fixed since the review, by the world moving on

- ~~**Three pre-existing failures the review documented and left red**
  ("0.4.1 ships with these three red"):
  `live_data_form_integration_test.exs:447,474` (a non-map `"data"` value lost
  `tools` and still fired `{:live_data_form, :submitted, _}`) and
  `entity_data_trash_test.exs:379` (`bulk_delete` raised `Postgrex.Error`
  23001 instead of returning `:referenced_by_external`).~~ Re-ran both files:
  **51 tests, 0 failures**. The malformed-payload guard and the
  RESTRICT-violation path both behave as the tests demanded.

## Verified, unchanged

- The `attr_key/3` / `created_by_key/1` atom-vs-string handling the review
  called "the subtle part" is intact, as is the test pinning that an anonymous
  submission is not filed in the auto-filled creator's audit trail.
- The `catch _, _ -> false` beside `rescue` — an unreachable database raises on
  an unowned checkout but *exits* on a dead pool — is still there. (Worth
  noting: the same sweep found `phoenix_kit_comments` missing exactly this on
  its own soft-failure paths. This module got it right.)

## Skipped (with rationale)

- **The `:needs_unreleased_core` tag and the `anonymous_creator_supported?/0`
  branches stay.** The review's follow-up condition — "when the pin's minimum
  reaches a core that guarantees V169" — has **not** been met: `mix.exs` still
  declares `pk_dep(:phoenix_kit, "~> 2.0")` (`mix.exs:122`), and
  `core_pin_conformance_test.exs` actively asserts that requirement admits
  `2.0.0`. A host can still legitimately run this module against a core whose
  chain is at V135, where the auto-fill is the *correct* behaviour. Removing
  the branches now would break those hosts; narrowing the pin to force the
  issue is what the conformance guard exists to prevent.

  Confirmed the excluded half still passes when asked for:
  `mix test --include needs_unreleased_core
  test/phoenix_kit_entities/entity_data_created_by_test.exs` → **16 tests, 0
  failures**.

## Files touched

None. This pass was verification only.

## Verification

| Step | Result |
|---|---|
| `mix test` | 1147 tests, 0 failures, 2 excluded |
| `mix test --include needs_unreleased_core` (created_by file) | 16 tests, 0 failures |
| the two previously-red files | 51 tests, 0 failures |
| `mix precommit` | passes |

## Open

None.
