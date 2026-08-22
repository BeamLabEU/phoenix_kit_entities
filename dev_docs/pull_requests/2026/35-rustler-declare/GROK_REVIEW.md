# Grok Review — PR #35 "Declare rustler explicitly so mdex_native force-builds"

**Merge commit:** a9bcc71
**Author:** timujinne (`upstream-fixes/rustler-declare`)
**Files:** `mix.exs`, `mix.lock`

## Summary of the change

`MDEX_NATIVE_BUILD=1` forces `mdex_native` (pulled in transitively through
`phoenix_kit`'s `mdex` dep) to build its NIF from source when no precompiled
build exists for the running OTP. That path requires `rustler` itself, not
just `rustler_precompiled`. Optional dependencies of dependencies are never
resolved, so a clean checkout of this package as the Mix root failed to
compile without a direct declaration.

Same one-line declaration core already carries:

```elixir
{:rustler, ">= 0.0.0", optional: true}
```

`mix.lock` pins `rustler` 0.38.0.

## Findings

None. The declaration matches `phoenix_kit`'s `mix.exs`, is optional so
Hex consumers are not forced to fetch it, and does not change
`mdex_native`'s force-build gate (`MDEX_NATIVE_BUILD` in `["1", "true"]`).
Having rustler present without that env still uses the precompiled NIF.

## Verified, no change needed

- **Why this package has to declare it.** Mix never fetches optional deps
  of deps. `phoenix_kit` already lists rustler as optional; that does
  nothing for *this* repo when it is the Mix root (CI, `mix test`, a
  contributor's clean checkout). Declaring it here is the root-project
  fix. Host applications that consume `phoenix_kit_entities` still have
  to declare rustler themselves — the PR body is explicit about that,
  and Hex optional-of-a-dep semantics confirm it.
- **Does not force a source build.** `deps/mdex_native/mix.exs` sets
  `optional: not @force_build?` from `MDEX_NATIVE_BUILD`. rustler on the
  path is necessary for the force-build, not sufficient to trigger it.
- **Constraint vs mdex_native.** This package uses `>= 0.0.0` (core's
  spelling). `mdex_native` wants `~> 0.32` when force-building. The
  lockfile's 0.38.0 satisfies both; Mix resolution still sees
  mdex_native's constraint once rustler is in the tree.
- **`runtime: false` not added.** rustler is a compiler. Core does not
  set `runtime: false`; this declaration is deliberately the same line.
- **`deps.unlock --check-unused`.** rustler is a direct dep, so it is
  not an unused lock entry. Optional does not make Mix treat it as
  unused.
