---
feature: advanced-polling
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - 2026-09-17-advanced-polling/PLAN.md
  - 2026-09-17-advanced-polling/LOG.md
---

# Review — polling evidence + settings-API recommendations

## polling evidence + settings API recommendations (2026-09-17)

*Migrated from the pre-`worknotes/` archive note `reviews/2026-09-17-settings-api-recommendations.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

Evidence base: [afanctl polling evidence](LOG.md). Plan:
[the plan](PLAN.md).

## Findings

1. **afanctl polls at 1 s** (configured = default = observed). The daemon's
   hardware poll interval is therefore *not* a knob omafan needs to touch for
   this work, and changing it is explicitly future work per the scope ruling.
2. **afanctl already exposes its poll interval read-only.** `afanctl status
   --json` includes `config.interval_s` and `config.source`. A future "show the
   daemon's hardware poll interval" feature needs **zero** afanctl changes.
3. **omafan's refresh interval is already a shell setting.** `poll_seconds`
   (int 1–10, default 2) exists in the manifest schema, is persisted in
   `shell.json`, and `Panel.qml` already consumes it with a 1–10 clamp. The
   Advanced toggle is therefore an *addition on top of a working setting*, not
   new persistence plumbing.
4. **The shell's schema types needed for the toggle are proven installed.**
   Built-in widget manifests on this machine use:
   - `boolean` — `Indicators.manifest.json`: `{"key":"alwaysShow",
     "type":"boolean","label":"Always Show","defaultValue":false}`
   - `integer` with `min`/`max`/`step` — agents panel:
     `{"key":"refreshIntervalSec","type":"integer","min":30,"max":3600,
     "step":30,"defaultValue":900}`
   - `enum` — agents panel: `{"key":"syncMode","type":"enum",
     "options":["Off","On"],"defaultValue":"Off"}`
   - `string` with `defaultValue`.
   Note the built-ins spell it `type: "integer"` + `defaultValue`, while
   omafan currently uses `type: "int"` + `default` and that already passes
   `omarchy plugin validate` and works with `omarchy bar set`. The shell
   appears to accept both; T3 must verify live which spelling the settings UI
   renders and standardise deliberately.

## Concrete recommendations

1. **Toggle key** — add one schema entry, either:
   - `{ "key": "poll_mode", "type": "enum", "label": "Refresh interval",
     "options": ["auto", "custom"], "default": "auto" }` (recommended: the
     two states are visible and self-describing), or
   - `{ "key": "poll_custom", "type": "boolean", "default": false }`.
   Keep `poll_seconds` (int 1–10, default 2) as the custom value. Auto mode
   = fixed 2 s; custom mode = `poll_seconds` clamped to whole seconds 1–10.
2. **Persistence** — shell settings only (`manifest.json` schema →
   `shell.json`). No side files, no `--config` for the panel.
3. **Contract discipline** — the manifest block is frozen in `DESIGN.md §1`
   and mirrored in `README.md`, `docs/INSTALL.md`, `docs/TROUBLESHOOTING.md`,
   `docs/ARCHITECTURE.md`, `manifest.json`, and asserted verbatim in
   `tests/manifest.test.sh`. A new key needs a `DEVIATIONS.md` ruling entry
   (old → new → why → affected tickets) and every mirror must move in the
   same changeset.
4. **Backward compatibility** — existing `shell.json` entries (`poll_seconds`)
   must keep working; the default (`auto`/2 s) must be what users get without
   touching anything.
5. **Model.js stays pure** — put the mode math (auto ⇒ 2, custom ⇒ clamp) in
   `Model.js` as an ES5-safe function if the panel consumes it there, and cover
   it in `tests/model.test.mjs`; no Qt imports, no I/O.
6. **Slider race (related bug, same release)** — the Auto-reset fix and its
   debounce-race regression (T2) share the panel's pending/status pipeline with
   T3; implement T2 first so the new mode can't resurrect the same stale-doc
   repopulation path.

## Out of scope, recorded for later

- afanctl hardware polling control (`interval_s`) — future work; if pursued,
  document in the afanctl Obsidian folder. The read-only display hook already
  exists (`config.interval_s` / `config.source` in `afanctl.status.v1`).
