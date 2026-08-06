# Follow-up Items for PR #25

Triaged against `main` on 2026-08-06. `CLAUDE_REVIEW.md` raised 6 findings;
5 are fixed in this batch, 1 is deliberately left open with rationale.

## Fixed (2026-08-06)

- ~~**#1** the `file` field type is the one registry type both new
  whitelists miss, and it *is* rendered~~ —
  `lib/phoenix_kit_entities/components/live_data_form.ex`,
  `lib/phoenix_kit_entities/form_builder.ex`. `@scalar_value_types` and
  `EntityData`'s type dispatch were cross-checked against
  `FieldTypes.all/0`: every one of the 13 registry types has an explicit
  rule in both layers except `file`, which fell to each catch-all. The
  catch-all's own comment claimed nothing stringifies those values — but
  `file` has no `readonly_field/3` clause, so it lands on the catch-all
  clause and `readonly_value/1`'s `to_string/1`, and
  `FormBuilder.build_field/3`'s `file` clause indexes each list entry
  (`file["filename"]`), which raises `FunctionClauseError` on a binary.
  Nothing in this library produces `file` data (upload placeholder, no
  `consume_uploaded_entries/3` anywhere), and any non-`heading` field can
  be added to `public_form_fields`, so `data[attachment][]=x` on the
  un-authed POST stores a list of strings that then breaks the admin
  editor for that record. Fixed with an explicit `:drop` clause for
  `file`/`image`/`relation` in `sanitize_field_value/2` (none render a
  submittable input, and a dropped key leaves `record.data`'s existing
  value untouched in the merge) plus `for file <- @current_files,
  is_map(file)` in the render clause. Tests in `live_data_form_test.exs`
  (sanitizer, DB-free) and `form_builder_render_test.exs` (render, both
  well-formed and mixed entries).

- ~~**#2** the write-side gates are ingress-only; already-stored bad values
  still crash the readonly view~~ —
  `lib/phoenix_kit_entities/components/live_data_form.ex`. Rows poisoned
  before this PR, rows written by a parent app calling `EntityData`
  directly, and anything under a `file` key all still hold whatever they
  hold; the readonly view is where they get rendered, and it ended in a
  bare `to_string/1` / `Enum.join/2`. The `select`/`radio` clause was worst:
  `FormBuilder.translated_option_label/3` deliberately falls back to the
  raw stored value (that's the `allow_other` free-text case), so a map went
  straight into `{@display}`. Fixed with a total `safe_string/1` (binary
  as-is, atom/number via `to_string/1`, everything else via `inspect/1`) on
  `readonly_text/1`, `readonly_value/1`, `readonly_list/1`'s join, and the
  `select`/`radio` display — the same `inspect/1` fallback the PR itself
  introduced as `stringify_invalid_option/1` in `EntityData` and
  `FormBuilder`. New DB-free describe block in `live_data_form_test.exs`
  covers `text`, `textarea`, `select`, `checkbox` and `file`.

- ~~**#3** the public controller crashes on crafted payloads before the
  changeset gate it's said to rely on~~ —
  `lib/phoenix_kit_entities/controllers/entity_form_controller.ex`. The
  changeset guard is justified in-comment as covering the public form, but
  four spots in `submit/2` trusted the request shape and raised first, each
  an un-authed 500: `get_in(params, ["phoenix_kit_entity_data", "data"])`
  (Access on a binary), `merge_other_params/2`'s `when is_map(params)`
  clause head, `generate_submission_title/2` handing a map to
  `generate_slug/1`'s `String.downcase/1`, and `get_time_to_submit/1`
  handing one to `DateTime.from_iso8601/1` — the last inside the
  security-check phase, i.e. on every public submission. Fixed with a
  pattern-matched `extract_form_data/1` (same "malformed degrades to empty"
  contract as `LiveDataForm.extract_data_params/1`), a binary-only title
  candidate check, an `is_binary/1` guard on `_form_loaded_at`, and a
  binary-or-nil `cap_metadata_param/1` so a crafted map doesn't reach the
  metadata JSONB either. One test per crash site in
  `entity_form_controller_test.exs`.

- ~~**#5** catch-all comment cites two types that aren't in the
  registry~~ — `image` and `relation` have `build_field/3` render clauses
  but no `FieldTypes` entry, so they can only come from a hand-edited
  `fields_definition`. Comment corrected; the new `:drop` clause covers all
  three regardless.

- ~~**#6** (pre-existing, not from PR #25) `main`'s gate and test suite
  were both red~~ — `mix.lock`,
  `test/phoenix_kit_entities/html_sanitizer_test.exs`. Both traceable to
  the `lib upgrades` commit (`a88cbf3`) that landed after the merge.
  `mix deps.unlock --check-unused` failed on eight orphaned entries
  (`igniter`, `sourceror`, `rewrite`, `spitfire`, `owl`, `glob_ex`,
  `ex_ast`, `text_diff`) — same class as PR #24's finding #2 and PR #21's
  finding #1 — fixed with `mix deps.unlock --unused`. Two
  `html_sanitizer_test.exs` tests asserted byte equality against the old
  `PhoenixKit.Utils.HtmlSanitizer` output; the upgraded dependency now adds
  `rel="noopener noreferrer"` to links and inserts the implied `<tbody>` in
  tables (upstream hardening / HTML-spec normalization, not regressions).
  Rewritten to assert the surviving element and safe attributes so the next
  upstream bump doesn't break them again.

## Open

- **#4** `EntityData.changeset/2` still has no shape opinion on `file`.
  Deliberate. This library never writes `file` data, so its stored shape is
  defined entirely by whichever parent app populates it — a strict
  list-of-maps gate at the changeset would be a guess and would reject data
  that works today. With the ingress closed for `LiveDataForm` and both
  render surfaces made total (#1, #2), storing an odd term under a `file`
  key has no crash consequence, which is the part that mattered. Revisit if
  and when this module grows real upload handling and owns the shape.

## Gate

`mix precommit` (`compile --force --warnings-as-errors` + `deps.unlock
--check-unused` + `hex.audit` + `format --check-formatted` + `credo
--strict` + `dialyzer`) passes clean: 0 compile warnings, 0 unused locks,
no retired/advisory packages, formatted, 0 credo issues, 0 dialyzer errors.

`mix test` runs 419 unit tests green — up from 413 with 2 failures before
this batch (finding #6's two, plus 6 new cases here). The 612 `:integration`
tests auto-exclude in this sandbox — no PostgreSQL server is installed, so
`test_helper.exs` takes its documented "DB unavailable" path. The new
`entity_form_controller_test.exs` and `form_builder_render_test.exs` cases
are in that excluded bucket (both files are `DataCase`-based by design);
the equivalent behavior for findings #1 and #2 is also covered by the
DB-free `live_data_form_test.exs` cases, which do run here.
