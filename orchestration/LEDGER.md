# orchestration/LEDGER.md — flight recorder

One line per dispatch, verification, rejection, ruling and commit. Newest first.
Format: `<time> <actor> <event> — <evidence command> — <result>`

- 2026-09-15T03:15Z orchestrator P0 recon complete — `hyprctl binds -j`, `afanctl status --json`, `plugins.omarchy.org/catalog.json`, `omarchy plugin --help`, `omarchy-shell omaplug refresh` — 175 bound chords, afanctl 0.1.0 active in observe, 6 sibling fan plugins surveyed, third-party IPC confirmed working; contracts frozen in DESIGN.md.
