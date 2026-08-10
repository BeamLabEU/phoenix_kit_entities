# PR #26 — Contribute a Data tab to the projects hub, repair the suite, slug records in their own language

**Reviewed:** 2026-08-10 · **Author:** mdon · **Verdict:** merged, **with a fix
applied on `main`.** Released in **0.3.0**.

+296 / −68 across 8 files. Reviewed as part of the phoenix_kit 2.0 sweep.

## Accepted

The **Data tab** contribution (`phoenix_kit_project_extensions/0` +
`Web.ProjectDataLive`) follows the same duck-typed, one-way discovery contract
as the Sites tab in `phoenix_kit_locations#10` — the projects package finds the
function, and this package gains no dependency on projects. Suite repairs and
the sitemap-source test addition are straightforward.

The **`transliterate: true` fixes are real and valuable.** Three call sites
(`Mirror.Importer.generate_slug_if_missing/3`,
`Mirror.Importer.preview_generated_slug/1`, and the data-form slug path) were
calling core's `Slug.slugify/1` without it. Core's option defaults to `false`,
after which the `[^a-z0-9]+` pass deletes every non-ASCII character — so a
Cyrillic or Greek title slugged to `""`. Same class of defect as
`phoenix_kit_document_creator#32`, which this sweep also merged.

## Correction: my "fix" to the `locale:` option was wrong, and is reverted

**The PR was right. I was wrong, and the error shipped in 0.3.0.**

On first review I removed the `locale:` option the PR passes to
`Slug.slugify/2`, on the grounds that core accepts only `:separator` and
`:transliterate` and would silently discard it. I ran an empirical check that
appeared to confirm this — German `Schön` came back `schon`, not `schoen`, at
every locale.

**That check ran against core 1.7.232.** This repo's `deps.update --all` had not
run yet at that point in the sweep, so the `PhoenixKit.Utils.Slug` I exercised
was the old hand-rolled table, which genuinely has no `:locale`. Core **2.0.0**
rewrote that module to delegate to the [`locale_slug`](https://hex.pm/packages/locale_slug)
package, and locale support is one of the headline reasons it did.

Re-run against core 2.0.0, which is what this release actually requires:

| Input | no locale | `locale: "de"` | `locale: "et"` |
|---|---|---|---|
| `Größe Fußball` | `grosse-fussball` | **`groesse-fussball`** | `grosse-fussball` |
| `Töö õun` | `too-oun` | **`toeoe-oun`** | `too-oun` |
| `Цветокоррекция` | `tsvetokorrektsiya` | `tsvetokorrektsiya` | `tsvetokorrektsiya` |

German expands `ö`/`ß` to `oe`/`ss`; Estonian folds them. The PR's comment —
"a German entry wants oe, an Estonian one o" — describes exactly this, and core's
own moduledoc gives the same examples. Passing `current_lang` is correct and the
parameter genuinely was being discarded before the PR.

**Reverted in 0.3.1:** `locale:` restored at both call sites, the `lang`
parameter restored through `auto_generate_entity_slug/4` and its three call
sites, and the comment rewritten to describe core 2.0's actual behaviour.

One thing kept from the revert: `auto_generate_entity_slug/4`'s `\\ nil` default
is removed, because every call site passes four arguments and
`--warnings-as-errors` rejects an unused default. That was latent in the PR.

Also worth recording, since it is the opposite of what I first wrote:
**`:transliterate` is now ignored by core** — romanization is always on in 2.0,
and the option is accepted only so existing call sites keep compiling. So the
`transliterate: true` in these calls is redundant rather than load-bearing. It
stays for consistency with the rest of the umbrella.

### What this means for the other slug work in this sweep

`phoenix_kit_document_creator#32` and `phoenix_kit_posts#15` are unaffected in
behaviour — passing `transliterate: true` is harmless under core 2.0, and their
diagnosis was right for the core they were written against. But the comments I
added to `phoenix_kit_posts` claiming `slugify/2` has no `:locale` are wrong for
core 2.0 and are corrected in posts 0.2.1.

## Verification

| Check | Result |
|---|---|
| `mix precommit` | **passes** against core 2.0.0, after the fix |
| `mix test` | **420 tests, 0 failures** (612 excluded — no Postgres available) |
