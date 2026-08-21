# Follow-up Items for PR #32

Reviewed against `main` on 2026-08-21. CLAUDE_REVIEW raised 2 findings. Fixed in
this batch.

## Fixed (Batch 1 — 2026-08-21)

- ~~**BUG - HIGH** decimal `min`/`max` bounds skipped entirely for integer/float
  input~~ — `FormBuilder.validate_type/2`'s integer and float clauses for
  `"decimal"` returned `{:ok, ...}` without ever calling `apply_decimal_bounds/2`,
  unlike the `%Decimal{}` and binary-string clauses. A raw numeric value (e.g. a
  JSON API body) bypassed the bounds check completely — the exact "negative money
  slips through" defect the type's bounds enforcement exists to prevent. Both
  clauses now bind `field` and route through `apply_decimal_bounds/2`. Pinned with
  a new test, `"enforces min and max for integer and float input, not just
  strings"`.
- ~~**IMPROVEMENT - MEDIUM** `"must be at least %{min}"` / `"must be at most
  %{max}"` never reached the gettext catalogues~~ — added to `default.pot` and
  `en`/`et`/`ru` `default.po`, with real et/ru translations, matching this repo's
  hand-maintained-catalogue convention.

## Verified, no change needed

The changeset guard's trim-before-parse fix from the prior external-review pass,
`decimal_input_value/1`'s non-scientific-notation rendering, the scale-to-step
derivation (including the `scale: 0` → `"any"` edge case), comma-decimal parsing
being scoped to the cast path only, the `to_decimal/1` vs. value-clause float
handling difference, and `FieldInput`'s reuse of the same render helpers as
`FormBuilder` — all checked directly against the merged code and held up. See
CLAUDE_REVIEW.md for specifics.

## Gate

`mix precommit` clean. `mix test`: 1123 tests, 0 failures.
