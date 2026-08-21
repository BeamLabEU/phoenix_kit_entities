# Review: PR #32 — Add a decimal field type

Merged as `ecf6423` (Max Don, `mdon/feat/decimal-field-type`). The branch already
carried a post-review hardening commit (`c063d0f`, "Harden the decimal type after
external review") fixing three findings from a prior adversarial pass — whitespace
in the changeset shape guard, float rendering through `to_string/1`, and a crash on
an unparseable `min`/`max` bound. This review re-checked the merged result rather
than re-litigating those.

New `decimal` field type: exact numeric (backed by `Decimal`, storage is the
canonical string form) for values `number`'s `Float.parse/1` cast would silently
round — money, primarily. Touches `field_types.ex` (registry entry + helpers),
`form_builder.ex` (cast/validate/render), `entity_data.ex` (changeset shape guard),
`components/field_input.ex` (inline-editor render).

## BUG - HIGH: min/max bounds skipped entirely for integer and float input

`FormBuilder.validate_type/2`'s `%Decimal{}` and binary clauses for `"decimal"`
both route through `apply_decimal_bounds/2`. The integer and float clauses did not:

```elixir
defp validate_type(%{"type" => "decimal"}, value) when is_integer(value),
  do: {:ok, Decimal.new(value)}

defp validate_type(%{"type" => "decimal"}, value) when is_float(value),
  do: {:ok, value |> Float.to_string() |> Decimal.new()}
```

Neither clause even bound `field` in its head, so bounds could not have been
checked without changing the pattern. `cast_field/2` and `validate_data/2` are
public API (`FormBuilder`'s moduledoc: "for hosts that own their own save
events") — a host passing a raw Elixir integer/float (e.g. a JSON API body, which
decodes numbers straight to native types rather than strings) bypassed `min`/`max`
completely. This is the exact defect the hardening commit's own message called
out as the reason bounds are enforced here: *"the first consumer is money, where a
negative slipping through is a real defect rather than a cosmetic one."*

Confirmed via `field(%{"min" => 0, "max" => "100.00"})` +
`FormBuilder.cast_field(bounded, -1)` → `{:ok, ...}` before the fix (should error).
Existing tests didn't catch it: "accepts an integer and an already-cast Decimal"
casts `12` against an unbounded field, and "enforces min and max" only exercises
string input (`"-1"`, `"100.01"`).

**Fixed** — both clauses now bind `field` and route through
`apply_decimal_bounds/2`, matching the `%Decimal{}` and binary clauses:

```elixir
defp validate_type(%{"type" => "decimal"} = field, value) when is_integer(value),
  do: apply_decimal_bounds(field, Decimal.new(value))

defp validate_type(%{"type" => "decimal"} = field, value) when is_float(value),
  do: apply_decimal_bounds(field, value |> Float.to_string() |> Decimal.new())
```

Added a regression test, `"enforces min and max for integer and float input, not
just strings"`, mirroring the existing string-input bounds test with numeric
literals.

## IMPROVEMENT - MEDIUM: two new gettext msgids never reached the catalogues

`apply_decimal_bounds/2` introduces `gettext("must be at least %{min}", ...)` and
`gettext("must be at most %{max}", ...)`. Neither msgid existed in
`priv/gettext/default.pot` nor in the `en`/`et`/`ru` `default.po` files — `et`/`ru`
users hitting a decimal bounds error would see the raw English interpolation
instead of a translation, same class of gap this repo has fixed before (per
AGENTS.md: "Add et/ru translations for field-builder msgids missing from
gettext"). `GettextCatalogueTest` doesn't catch this: it only guards entries that
already exist in the catalogue (no-fuzzy, no-empty-msgstr, bindings-subset) — it
has no "every msgid in the source is present" check, so a wholly new msgid that
never got added is invisible to it.

**Fixed** — hand-added both msgids (matching this repo's hand-maintained-catalogue
convention) to `default.pot` and to `en`/`et`/`ru` `default.po`, alphabetically
placed between `"must be a valid number"` and `"must be one of: %{options}"`, with
real et/ru translations (not copies of the English).

## Verified, no change needed

- **`decimal_shaped?/1` (entity_data.ex changeset guard)** trims before
  `Decimal.parse/1`, matching what `cast_field/2` accepts — the specific gap the
  prior hardening pass fixed (`" 5.1 "` round-trip). Confirmed correct; the guard
  intentionally does not re-check `min`/`max` (only `FormBuilder` enforces bounds,
  per its own comment — the changeset guard is a shape check on already-cast data,
  not a re-validation of the form-time bounds; this is a deliberate scope split, not
  an oversight).
- **`FieldTypes.decimal_input_value/1`** renders `%Decimal{}` and float values
  through `Decimal.to_string(:normal)` rather than `to_string/1`, avoiding the
  `1.0e-7` scientific-notation output an `<input type="number">` rejects. Checked
  against the actual `Decimal.to_string/2` implementation, not assumed.
- **`decimal_step/1` scale-to-step derivation** (`"0.0001"` for `scale: 4`, `"any"`
  for no/zero scale) matches the rendering tests and the stated rationale (browser
  step validation would otherwise reject the extra places the type exists to
  preserve). `scale: 0` falling through to `"any"` rather than `"1"` is a minor
  looseness (an integer-scale decimal accepts any step client-side) but does not
  affect server-side validation, which doesn't consult `step` at all — not worth a
  behavior change for a type whose main use case (money) always has scale > 0.
- **Comma-decimal parsing** (`"12,50"` → `12.50`) is applied on the `FormBuilder`
  cast path only, not the `entity_data.ex` changeset guard — correct, since by the
  time a value reaches the changeset it has already been cast to canonical (period)
  form or is a `%Decimal{}`; raw comma input never reaches that guard directly.
- **`to_decimal/1`'s float branch** (used only for parsing `min`/`max` bounds) uses
  `Decimal.from_float/1` directly rather than the `Float.to_string/1` route
  `validate_type`'s float value-clause uses. Different call sites, different needs:
  bounds come from an admin-edited field definition (numbers or strings in
  practice, float here would be unusual), while the value clause exists
  specifically to avoid carrying a float's full binary-precision expansion into
  stored data. Not a bug, just worth flagging as an inconsistency if `to_decimal`
  ever gets reused for value parsing.
- **`FieldInput`'s decimal render clause** delegates to the same
  `FieldTypes.decimal_input_value/1` / `decimal_step/1` helpers `FormBuilder` uses
  — no drift between the two render paths.

## Gate

`mix precommit` (compile --warnings-as-errors + credo --strict + dialyzer): clean.
`mix test`: 1123 tests, 0 failures.
