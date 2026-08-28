# PR #38 Review — I067: SchemaOwnerGuard

**Reviewer:** Claude
**Date:** 2026-08-28
**Verdict:** Approve

---

## Summary

Test-infrastructure-only PR (no `lib/` changes, so nothing here ships in the
Hex package). Adds `PhoenixKitEntities.Test.SchemaOwnerGuard`, wired into
`test/test_helper.exs`, to stop a `PGDATABASE`-override collision from
silently corrupting another package's `schema_migrations` bookkeeping:

- `check!/1` raises `OwnerMismatch` before migrating if the target DB's
  `schema_migrations` table carries someone else's `COMMENT ON TABLE`
  marker, and only when `PGDATABASE` is actually set.
- `stamp!/1` marks ownership unconditionally on every successful boot
  (including the default, non-overridden DB) so a *later* collision has
  something to detect. Degrades to a logged no-op under
  `insufficient_privilege` (a role that doesn't own the table) instead of
  breaking the boot.
- A wiring test (`schema_owner_guard_wiring_test.exs`) spawns a real nested
  `mix test` against scratch/cloned databases to prove `test_helper.exs`
  itself calls `check!`/`stamp!` — a unit test of the module alone can't
  distinguish "never wired in" from "just not exercised."

## Issues Found

None. The module correctly narrows `check!/1`'s effect to `PGDATABASE`-only
(never rejects the module's own isolated default DB) and rescues exactly
`Postgrex.Error{postgres: %{code: :insufficient_privilege}}` in `stamp!/1`,
reraising anything else. `disconnect_all/3` in the wiring test correctly
passes `pool: DBConnection.Ownership` (this repo's test pool runs under
Sandbox) — already the subject of `d6547a4` earlier in this same branch.

## Post-Review Status

No blockers. Ready for release (though this PR ships no `lib/` code, so
there is nothing new for the Hex package itself — see the combined release
notes with PR #39).
