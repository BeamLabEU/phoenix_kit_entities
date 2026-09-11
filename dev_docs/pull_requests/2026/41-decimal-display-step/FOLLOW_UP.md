# Follow-up Items for PR #41

Reviewed against `main` on 2026-08-30. CLAUDE_REVIEW raised 5 findings
(1 HIGH, 1 MEDIUM bug, 2 MEDIUM improvements, 1 NITPICK). Four fixed in this
batch, one deliberately left.

## Fixed (Batch 1 — 2026-08-30)

- **BUG - HIGH** `field_types.ex` — the merged override returned any explicit
  `"step"` verbatim, on the stated reasoning that "LiveView never runs the
  browser's step validation". It does: `step` is a validation constraint, a
  step-mismatched input sets `validity.stepMismatch`, and a form's `submit`
  event fires only after native validation passes. Both admin forms
  (`web/data_form.ex:1547`, `components/live_data_form.ex:742`) are plain
  `<.form phx-submit=…>` with no `novalidate`, and the public form is a native
  POST. So the PR's own example — `"step" => "0.01"` on a `scale: 4`
  `unit_cost` — left the browser refusing to submit `12.3456` and the record
  unsaveable: the exact bug the scale-derived step was added to prevent.
  `decimal_step/1` now honours an override only when it still admits every
  value the scale allows — `"any"` (no stepping; arrows walk by 1, all four
  places typeable — the supported cure for the crawling arrows that motivated
  the PR), or a step dividing `10^-scale`. A coarser one falls back to the
  scale. No declared `scale`, no promise to keep: the step stands.
  Covered by `"an explicit step that admits the declared scale is honoured"`,
  `"a step coarser than the scale falls back to the scale"` and
  `"an explicit \"any\" turns stepping off"` in `decimal_field_test.exs`.
- **BUG - MEDIUM** `field_types.ex` — the binary branch guarded only
  `step != ""`, so `"0"`, `"-0.5"`, `"abc"` and `"0,01"` reached the
  attribute; the browser then discards an invalid `step` and uses `1`,
  rejecting every decimal. The override is now parsed with `Decimal.parse/1`,
  must consume the whole string, and must be finite and positive. Covered by
  `"junk, zero and negative steps fall back to the scale"`, which enumerates
  ten such values — the PR's test asserted "junk falls back to the scale" but
  exercised only `""`, the one case that already did.
- **IMPROVEMENT - MEDIUM** `field_types.ex` — a float step rendered through
  `to_string/1`, which `decimal_input_value/1` two functions below exists to
  avoid (`to_string(0.00001)` is `"1.0e-5"`). The accepted step now renders
  through `Decimal.to_string(value, :normal)`. Also corrected the registry
  comment on `"step" => nil`, which asserted the wrong claim about step
  validation.
- **IMPROVEMENT - MEDIUM** `README.md` — pre-existing drift the PR's type sits
  inside: "12 field types" and a `Numeric | number` row, against a registry of
  16. Counts corrected, `decimal`, `image`, `video` and `heading` added, and
  the Numeric row now documents `scale` and `step`.

## Not fixed (deliberate)

- **NITPICK** no admin UI for `"step"` — the field editor
  (`web/entity_form.ex`) exposes neither `step` nor `scale`, and
  `new_field_form/0` does not merge `default_props`, so both are reachable
  only via `FieldTypes.new_field/4`, a managed blueprint, or direct JSONB.
  That matches how `scale` has always worked; adding a prop editor for one
  type is a bigger change than this PR calls for. Recorded so the override is
  not mistaken for something an admin can set from the UI.

## Known limitation

A number input cannot separate spinner granularity from step validation.
A field that wants cent-sized arrows must declare `"scale" => 2`; a 4-place
field's best available option is `"step" => "any"`.
