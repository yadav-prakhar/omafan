# QUESTIONS.md — open questions raised by workers or the orchestrator

Format: `Q<n> — <question> — raised by <ticket/agent> — status: open|answered <answer>`

Q1 — T01 gate `omarchy plugin validate .` exits 0 requires `BarWidget.qml` (the barWidget entry point), but that file is owned by T07 and does not exist at P1. The validate harness and manifest are correct; the gate will pass once T07 lands. — raised by T01 — status: open
