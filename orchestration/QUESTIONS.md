# QUESTIONS.md — requests from workers for files they do not own

## 2026-09-15, T04 (bin/omafan-ctl): DESIGN.md §7 chord command names a verb §4 does not define

- Where: DESIGN.md §7 vs DESIGN.md §4.
- What: the §7 global chord table wires `SUPER+ALT+C` to
  `omafan-ctl cycle --notify`, but the frozen §4 verb list has no `cycle`
  verb (only status|presets|doctor|preset|rpm|release|version). T04
  implements §4 exactly, so that chord's command currently exits 2 (usage).
- Request (either resolution works; pick one):
  (a) approve an additive `cycle [--notify]` verb on `bin/omafan-ctl`
  (reads state's current hold preset, walks the §3 ladder, wraps, writes);
  or (b) change the §7 `cycle` chord to a wrapper (e.g. a small shell
  pipeline over `omafan-ctl status`/`preset`) owned by T06.
- I implemented §4 as written (no `cycle`) per WORKER.md rule 5 until a
  ruling lands.
