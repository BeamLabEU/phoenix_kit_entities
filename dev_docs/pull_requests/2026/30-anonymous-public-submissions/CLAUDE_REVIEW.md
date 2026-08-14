# PR #30 Review — Store anonymous public submissions with no creator

**Author:** Max Don (mdon)
**Reviewed:** 2026-08-14 (ecosystem sweep)
**Verdict:** APPROVED — merged, with a gate fix; feature verified against the released core

---

## The bug, and why the fix is the right shape

`EntityData.create/2` auto-fills `created_by_uuid` "if not provided", but decided that
with `Map.has_key?/2`. The public entity form is deliberately unauthenticated and passed
`created_by_uuid` as an **explicit nil**, which `has_key?` reads as *provided* — so the
auto-fill was skipped and every anonymous submission died on a Postgrex 23502 raised out
of an unauthenticated controller.

The fix separates *absent* from *explicitly nil*: absent still auto-fills (internal
callers unchanged), explicit nil means "this row has no author" and is stored as NULL.

The rejected alternative is documented and I agree with the rejection: auto-filling the
first administrator puts a named person's address in front of every anonymous submission
wherever a creator is rendered, and files those submissions in that person's audit trail.
There is a test pinning exactly that (`"an anonymous submission is not filed in the
auto-filled creator's audit trail"`), which is the right thing to pin.

**The atom/string key handling is the subtle part and it is correct.** `attr_key/3`
picks the key form the caller is already using, because a map mixing atom and string
keys makes `cast/3` raise. The comment on `created_by_key/1` explains why choosing by
`:entity_uuid` alone would be wrong — it would answer `"created_by_uuid"` for a map
holding an explicit `created_by_uuid: nil` under the *atom* key, leaving the nil in place
beside a filled string key. That is a real trap, correctly avoided, and the same fix was
applied to `PhoenixKitEntities.maybe_add_created_by/1`.

The `catch _, _ -> false` alongside `rescue` is also right, and matches core's guidance:
an unreachable database *raises* on an unowned checkout but *exits* on a dead pool, so
`rescue` alone would let a public request crash.

---

## Findings

### BUG - LOW — the PR failed this repo's gate *(fixed on main)*

`mix precommit` exited 2 with **7** credo `--strict` findings, all "Nested modules could
be aliased at the top of the invoking module" on the PR's new test code:
`PhoenixKit.Test.Fixtures.*` and `PhoenixKit.Migrations.Postgres.*` called fully
qualified across three test modules in `entity_data_created_by_test.exs` and one in
`entity_form_controller_test.exs`.

Aliased per module (each `defmodule` needs its own). Gate now exits 0 with credo finding
no issues and zero unskipped dialyzer findings.

---

## Verified against the released core, including the tests CI skips

`EntityDataAnonymousCreatorTest` carries `@moduletag :needs_unreleased_core` and is
**excluded from every normal run** — which means the two tests that actually prove the
headline behaviour do not run by default:

- "an explicit nil creator is stored as NULL, not attributed to an admin"
- "omitting the key still auto-fills, so internal callers are unchanged"

Since core 2.4.0 (which ships V169) is now published and this repo's test database is at
chain version 169, I ran them explicitly:

```
mix test test/phoenix_kit_entities/entity_data_created_by_test.exs --include needs_unreleased_core
15 tests, 0 failures
```

**The feature works end to end against the released core.**

### The tag was deliberately left in place

Its moduledoc says to delete it "once core's floor is past V169". That has *not* happened
and must not be assumed: this module pins `{:phoenix_kit, "~> 2.0"}`, and
`core_pin_conformance_test.exs` actively asserts the requirement admits `2.0.0` and
`2.0.7`. So a host can legitimately run this module against a core whose chain is still
at V135, where `created_by_uuid` is NOT NULL and the auto-fill is the *correct*
behaviour.

Raising the pin to `~> 2.4` would have made the tests unconditional — and broken the
conformance guard, whose whole point is that narrowing the pin breaks `mix deps.get` for
consumers rather than anything in this repo. The runtime branch on
`Postgres.migrated_version_runtime/1` is the right mechanism here, and modules 1 and 2
already use it to assert the correct behaviour on *either* side of V169.

**Follow-up for whoever raises the floor:** when the pin's minimum does reach a core that
guarantees V169, delete the tag and the `anonymous_creator_supported?/0` branches
together.

---

## Pre-existing failures — NOT fixed, and not caused by this PR

`mix test` reports **3 failures out of 1060**, all verified pre-existing by re-running
the same two files at the pre-merge commit (`d030ddb`) with its own lockfile: same three.

1–2. `live_data_form_integration_test.exs:447,474` — "malformed payload guard (m2)": a
non-map `"data"` value both loses `tools` and still fires `{:live_data_form, :submitted,
_}`, which the test explicitly refutes. Reads as a genuine guard gap, not a stale test.

3. `entity_data_trash_test.exs:379` — `bulk_delete` raises `Postgrex.Error` 23001 instead
of returning `:referenced_by_external`, so the friendly-error path is not catching a
RESTRICT violation from an external table.

Left alone deliberately — unrelated to this PR and outside the sweep's scope. **0.4.1
ships with these three red.**

---

## Also in this release: the package stopped shipping its test droppings

Not from this PR. `priv/entities/` held **28 committed JSON files**, every one traceable
to a test (`imp_conflict_*`, `imp_sel_a_*`, `imp_via_storage_*` are literally
`"imp_conflict_#{System.unique_integer()}"`; `ctx_draft`, `ef_test`, `*_widget` come from
named test fixtures). They were swept in by a `git add -A` in the daisyUI commit
(`d030ddb`).

Because `mix.exs` declares `files: ~w(lib priv …)`, **all 28 were published to Hex and
landed in consumers' `priv/entities/` — the exact directory `Storage.default_path/0`
reads back**. Untracked and gitignored; `Storage.write_entity/2` calls `File.mkdir_p/1`,
so nothing depends on the directory pre-existing.
