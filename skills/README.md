# skills/

Task-shaped procedures for working in this repository — written for coding
agents, readable by humans. Each skill is a directory with a `SKILL.md` that has
YAML frontmatter (`name`, `description`) and a short, imperative body: what to
run, in what order, and which traps have already bitten this project.

| Skill | Use it when |
|---|---|
| [run-the-gates](run-the-gates/SKILL.md) | before claiming any change works; adding a test case or a suite |
| [live-verify-in-the-shell](live-verify-in-the-shell/SKILL.md) | checking a change against a running Omarchy session |
| [change-a-frozen-contract](change-a-frozen-contract/SKILL.md) | a behaviour change contradicts `DESIGN.md` |
| [capture-docs-screenshots](capture-docs-screenshots/SKILL.md) | refreshing README / wiki images from the real UI |
| [publish-a-release](publish-a-release/SKILL.md) | cutting a version and updating the marketplace listing |

## How an agent should use them

Read the skill that matches the task before editing, and follow its commands
literally — they were run on the reference machine and the outputs are quoted in
[CHANGELOG.md](../CHANGELOG.md), the `orchestration/` record and the feature's
[`worknotes/`](../worknotes/README.md) folder. The
per-directory `AGENTS.md` files ([root](../AGENTS.md), [bin](../bin/AGENTS.md),
[tests](../tests/AGENTS.md)) carry the invariants; the skills carry the moves, and
[`worknotes/`](../worknotes/README.md) carries the record of what was done.

If your agent runtime loads skills from a directory (Hermes, Claude Code, and
similar), point it at this folder or copy/symlink the directories into its skill
path:

```sh
# Hermes Agent
cp -r skills/run-the-gates skills/live-verify-in-the-shell ~/.hermes/skills/
```

## Adding a skill

Add a directory with a `SKILL.md` whose `description` starts with the trigger
(`Use when …`), then add a row to the table above. Keep one procedure per skill,
state the command that proves each step, and record the pitfall you actually hit
— not the general advice around it. Skills that describe stale commands are worse
than no skill at all, so re-run the commands when you touch one.
