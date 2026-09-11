# PR #41 Review — A display step override for decimal fields

**Reviewer:** Claude
**Author:** Max Don
**Merge:** `ef0689d` (branch `mdon/main`, commit `a0646e1`)
**Date:** 2026-08-30
**Verdict:** Request changes — the override as merged reintroduces the exact
bug `decimal_step/1` was written to prevent. Fixed in place, with the
override kept but constrained.

---

## Summary

Two changes: `"step" => nil` joins the `decimal` type's `default_props`, and
`FieldTypes.decimal_step/1` now returns an explicit `"step"` prop verbatim
(binary, or `to_string/1` of a positive number) instead of always deriving
the step from the declared `scale`. One test covers the new branch.

The motivation is real and worth solving: a `scale: 4` money field renders
`step="0.0001"`, so the number input's spinner arrows walk a ten-thousandth
at a time — useless on a supplier `unit_cost`.

---

## Findings

### BUG - HIGH — a coarser step blocks submission of the values the scale exists to keep

`field_types.ex:774-802` (as merged). The change rests on a claim written
into both the registry comment and the doc:

> typed values keep the full scale either way, since LiveView never runs the
> browser's step validation.

That is not so, and the doc comment three lines above it — kept from the
original implementation — says the opposite: *"Without this the browser
rejects the extra decimal places the type exists to preserve."* Both cannot
be true, and the original is the correct one.

`step` on `<input type="number">` is not just the spinner's granularity: it
is a validation constraint. A value that is not a multiple of it sets
`validity.stepMismatch`, and a form's `submit` event fires **only after**
native constraint validation passes. Every form that renders these fields is
an ordinary `<form>` with no `novalidate`:

- `web/data_form.ex:1547` — `<.form … phx-submit="save">`
- `components/live_data_form.ex:742` — `<.form … phx-submit="submit">`
- the public form, built from `FormBuilder.build_field/2` and POSTed to
  `/entities/:entity_slug/submit` — a native submit, so the same rule applies
  before the request is even made.

So with the PR's own headline example — `"scale" => 4, "step" => "0.01"` on
`unit_cost` — typing `12.3456` leaves the browser refusing to submit
("Please enter a valid value. The two nearest valid values are 12.34 and
12.35"); LiveView never receives the event and the admin cannot save the
record at all. That is precisely the failure `decimal_step/1` exists to
prevent, reached through the new escape hatch. (Autosave via `phx-change` on
`live_data_form` softens the data loss but not the broken submit.)

There is no HTML that decouples spinner granularity from step validation, so
the feature cannot be delivered as specified. **Fixed** by honouring the
override only when it still admits every value the scale allows:

- `"any"` — no stepping at all. This is the actual cure for the crawling
  arrows: browsers step an `any` field by 1, and all four places stay
  typeable. It is now the documented answer to the motivating complaint.
- a step that divides `10^-scale` (`"0.0001"`, `"0.00005"` on a 4-place
  field) — finer or equal, so nothing legal is rejected.
- anything coarser falls back to the scale-derived step.

With no declared `scale` there is no promise to keep, so an explicit step
stands as given.

### BUG - MEDIUM — the explicit binary branch validated nothing

The numeric clause guarded `step > 0`; the binary clause guarded only
`step != ""`. So `"step" => "0"`, `"-0.5"`, `"abc"`, `"0,01"` (plausible — the
type's own cast path accepts a comma separator) all rendered straight into
the attribute. An invalid `step` is not inert: the browser discards it and
falls back to `step="1"`, which again rejects every decimal the field is for.
The PR's test comment claims "junk falls back to the scale", but `""` was the
only junk that did.

**Fixed** — the override is parsed with `Decimal.parse/1` and must consume
the whole string, be finite and positive; everything else falls back to the
scale-derived step. The test now enumerates `""`, `" "`, `"abc"`, `"0"`,
`"-0.01"`, `"0,01"`, `"0.0001x"`, `"Infinity"`, `0` and `-1`.

### IMPROVEMENT - MEDIUM — `to_string/1` on a float step

The numeric branch rendered floats with `to_string/1`, two functions above
`decimal_input_value/1`, which exists to avoid exactly that: *"a small float
stringifies as `1.0e-7`"*. `to_string(0.00001)` is `"1.0e-5"`. HTML's
floating-point grammar does tolerate an exponent, so this was cosmetic rather
than broken — but it contradicts the module's own stated rule. **Fixed**:
the accepted step renders back through `Decimal.to_string(value, :normal)`.

### NITPICK — the override has no admin UI

`"step"`, like `"scale"`, is settable only through `FieldTypes.new_field/4`,
a managed blueprint, or direct JSONB — the field editor in
`web/entity_form.ex` renders no input for either, and `new_field_form/0` does
not merge `default_props`. Consistent with `scale`, so **not changed**;
recorded so it is not mistaken for a UI feature.

### IMPROVEMENT - MEDIUM — README field-type drift (pre-existing)

Not this PR's doing, but this PR extends the type the drift hides: `README.md`
still advertised "12 field types" and a table with `Numeric | number`, four
types after the registry moved on (`decimal`, `image`, `video`, `heading`).
**Fixed** — counts corrected to 16, the missing types listed, and the Numeric
row now documents `decimal`'s `scale` and `step`.

---

## Verification

- `mix test test/phoenix_kit_entities/decimal_field_test.exs` — 26 tests, 0
  failures.
- `mix precommit` — clean.
