# PR #33 follow-up — Use core's `nav_tabs` for the icon category filter

Triaged 2026-08-28 as part of the four-repo quality sweep.

## No findings

`GROK_REVIEW.md` reported **none**, on the grounds that the
handler/template/test triple stays in sync and nothing else emits
`filter_by_category`. Re-verified against current code, since that is exactly
the kind of agreement that silently rots:

- the handler takes the component's standard payload key —
  `handle_event("filter_by_category", %{"tab" => category}, …)`
  (`web/entity_form.ex:400`);
- the strip is core's component, with a comment recording why —
  `<.nav_tabs … on_change="filter_by_category">` (`:3332-3334`);
- the live test drives the same key —
  `render_hook(view, "filter_by_category", %{"tab" => "general"})`
  (`test/phoenix_kit_entities/web/entity_form_live_test.exs:220`);
- and `filter_by_category` still has exactly one emitter and one handler
  across `lib/` and `test/`.

## Verification

| Step | Result |
|---|---|
| `mix test` | 1147 tests, 0 failures, 2 excluded |
| `mix precommit` | passes |

## Open

None.
