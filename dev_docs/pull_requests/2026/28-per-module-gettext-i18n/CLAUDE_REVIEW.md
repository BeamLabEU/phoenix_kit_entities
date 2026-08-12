# Claude Review — PR #28 (per-module Gettext i18n) and PR #29 (test DB from env)

Reviewed 2026-08-12 as part of the ecosystem PR sweep. Both merged into `main`.

**Verdict: both APPROVED.** PR #28 catches a packaging bug that would have made
the whole feature invisible to consumers, and fixes a real locale-dependent UI
bug on the way past. One gate failure it introduced was fixed before release,
along with a pre-existing version drift.

## PR #29 — Read test DB name and pool size from the environment

`config/test.exs` plus an `AGENTS.md` note. Same mechanism as core
`phoenix_kit`'s `config/test.exs` and the sibling changes in `phoenix_kit_ai`
#18, `phoenix_kit_catalogue` #58 and `phoenix_kit_dashboards` #8 — reading
through a `case` on `System.get_env/1` so a set-but-empty `PGPOOL=` falls back
instead of aborting config loading with an `ArgumentError` that never names the
variable. Defaults preserved. Nothing to fix.

## PR #28 — Per-module Gettext i18n (en/ru/et)

**The backend switch is complete.** Audited every file in `lib/` containing a
`gettext`/`ngettext`/`gettext_noop` call — 14 files, all 14 carrying `use
Gettext, backend: PhoenixKitEntities.Gettext`. None left on core's backend.

**The catalogues are mechanically sound.** Parsed all three `.po` files:

| Check | en | et | ru |
|---|---|---|---|
| Entries | 487 | 487 | 487 |
| `fuzzy`-flagged | 0 | 0 | 0 |
| Empty `msgstr` | 0 | 0 | 0 |
| `%{...}` placeholder mismatch | 0 | 0 | 0 |

Plural handling is right: 7 plural msgids per locale, each with a full
`msgstr[2]` in ru and none in en/et.

### The packaging catch is the most valuable thing in this PR

`mix.exs` had:

```elixir
files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
```

No `priv`. Every `.po` and the `.pot` live under `priv/gettext/`, so without
this PR's change to add it, the entire translation feature would have been
absent from the Hex tarball — the package would compile, the backend would
exist, and every install would render raw English msgids regardless of locale,
with nothing in the build output to suggest why. This is the kind of defect
that survives a green CI run and only surfaces as a bug report from a consumer.

### `for_picker/0`'s reordering was a genuine bug

The old implementation ended with `Enum.sort_by(& &1.category)` — sorting by
the **translated** category label. That makes the field-type picker's grouping
order depend on the active locale: English orders "Date & Time" before
"Choice", while Estonian's "Kuupäev ja aeg" sorts after "Valik". Users of
different languages would see the same picker in different orders, and the
order would have shifted the moment translations landed.

It now builds a `category_order` index from `category_list/0` and sorts by
that, which is locale-independent. Correct fix, and the `@doc` records the
reasoning so it does not regress.

### `label_for/1` is written the right way

Thirteen literal clauses rather than `gettext(type.label)` over the
`@field_types` map. That looks repetitive but is required: `mix gettext.extract`
scans for literal arguments, so passing a variable would leave every field-type
label unextracted and permanently untranslated. The `@doc` says exactly this,
matching the existing `description_for/1` precedent in the same module.

No red flags against the Phoenix skill's checklist: no queries added to
`mount/3`, no PubSub topics touched, no `terminate/2` or `start_async` usage.

## Fixed on `main`: PR #28 left the gate red

`mix precommit` failed at dialyzer after the merge, with exactly one warning
type: `lib/phoenix_kit_entities/gettext.ex:1:call_without_opaque`. Gettext 1.0 +
Expo 1.1 generate a `Gettext.Plural.plural/2` call against Expo's **opaque**
`PluralForms` struct inside the code `use Gettext.Backend` writes — three
warnings, one per locale's plural form.

Known upstream false positive in code nobody here authors; every sibling
package owning a Gettext backend already carries the same skip. Added
`.dialyzer_ignore.exs` scoped to that one file and that one warning type, and
wired `ignore_warnings:` into `mix.exs`. Dialyzer now reports `Total errors: 3,
Skipped: 3, Unnecessary Skips: 0`.

`phoenix_kit_dashboards` #7 had the identical omission in the same sweep — the
per-module-i18n guide should list the dialyzer skip as a required step
alongside the backend module and the `files:` entry, since two independent
retrofits missed it the same way.

## Fixed on `main`: `version/0` was three releases stale

`PhoenixKitEntities.version/0` returned `"0.2.10"` while `mix.exs` declared
`@version "0.3.2"` — so **0.3.0, 0.3.1 and 0.3.2 all shipped reporting
0.2.10**. Predates both PRs, and nothing in the suite asserted it, so nothing
ever failed.

Rather than just correcting the string, `version/0` now derives from
`Mix.Project.config()[:version]` at compile time:

```elixir
@version Mix.Project.config()[:version]
def version, do: @version
```

which makes the drift unrepresentable rather than merely fixed. This is the
pattern `phoenix_kit_document_creator` already uses, and it is why that repo
has never had this bug. Added a test pinning the derivation so a future revert
to a hardcoded string fails the suite.

This is the third instance of the same defect class in this one sweep —
`phoenix_kit_ai` shipped it in 0.18.1, `phoenix_kit_catalogue` in 0.14.0, and
here it ran for three releases. Every module still hardcoding the string in a
second place is one careless bump away from repeating it; converting them to
the compile-time derivation would retire the class outright.
