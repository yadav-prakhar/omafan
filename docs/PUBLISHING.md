# PUBLISHING.md — marketplace submission package

This document contains everything needed to list omafan on
[plugins.omarchy.org](https://plugins.omarchy.org), and the release flow that
puts a version on the shipped branch in the first place. The operator copies the
issue body verbatim into the marketplace's GitHub issue form after pushing the
public repository.

Branch model, in one line: work lands on `dev` (the default branch); `master` is
the shipped branch and is updated only by the curated sync in §2 — never by a
merge. [DEVIATIONS.md](../DEVIATIONS.md) R11 states why, R13 states how.

---

## 1. Prerequisites (pre-submit checklist)

- [ ] Repository `https://github.com/yadav-prakhar/omafan` is **public**.
- [ ] Root `manifest.json` is present and `omarchy plugin validate .` exits 0.
- [ ] `README.md` is present and covers: what it is, requirements, install,
      usage, keyboard shortcuts, safety model, uninstall.
- [ ] `LICENSE` is present and contains the GPL-3.0 full text.
- [ ] `bin/omafan-ctl`, `bin/omafan-keybindings`, `BarWidget.qml`,
      `Panel.qml`, `KeyboardHelp.qml`, and `Model.js` contain no TODO or
      placeholder text.
- [ ] `tests/run-all.sh` passes with all suites green.
- [ ] `omarchy plugin validate .` exits 0.
- [ ] `qmllint -I /usr/share/omarchy/shell` is clean on every shipped QML file.
- [ ] No secrets, personal tokens, or `/etc/` paths appear in the tree
      (`grep -r` check done).
- [ ] The plugin installs cleanly with
      `omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable`
      and removes cleanly with
      `omarchy plugin remove io.github.yadav-prakhar.omafan`.
- [ ] `bash tests/branch-model.test.sh` is green: the tree of `master` carries no
      development path. Users clone the **whole repository**, so this is the check
      that keeps `worknotes/`, `skills/`, `orchestration/` and every `AGENTS.md`
      out of a stranger's installation.

Everything above is run against the tree that will actually ship, which means
*after* the §2 sync — `master`, not `dev`. The quickest way to see what a user
gets is to clone it:

```sh
git clone --branch master --single-branch \
  https://github.com/yadav-prakhar/omafan.git /tmp/omafan-shipped
cd /tmp/omafan-shipped
omarchy plugin validate .
bash tests/run-all.sh
```

## 2. Release: the curated sync onto `master`

`master` is what `omarchy plugin add` clones into `~/.config/omarchy/plugins/<id>`.
A release copies an allowlist of shipped paths from `dev` onto `master` as one
commit and tags it. It is **never** a `git merge`: a merge would put
`worknotes/`, `orchestration/`, `skills/`, `PLAN.md`, `QUESTIONS.md` and every
`AGENTS.md` into every user's installation, where their coding agent can read and
act on it (ruling R11; the sync is R13's replacement for R11's prohibition).

```sh
# 1. land everything on dev, version bumped, gate green
bash tests/run-all.sh

# 2. review what the release would change on master — writes nothing
skills/publish-a-release/sync-master.sh --from dev
skills/publish-a-release/sync-master.sh --from dev --full-diff

# 3. write it as one commit, and tag it
skills/publish-a-release/sync-master.sh --from dev --commit --tag vX.Y.Z

# 4. prove the shipped tree is clean, then push
bash tests/branch-model.test.sh
git push origin master --follow-tags
```

The script copies only `OMAFAN_SHIPPED_PATHS`, prunes every denylisted path the
allowlist swept up, and **refuses to write if any denylisted path survives**.
Both lists live in `tests/lib/shipped-paths.sh`. Running it twice changes
nothing. The version bump and the wiki refresh are in
`skills/publish-a-release/SKILL.md` (on `dev`).

## 3. Repository commands (operator may re-run)

```sh
# Create the public repo (one-time; skip if already created)
gh repo create yadav-prakhar/omafan --public --license GPL-3.0-only \
  --description "Fan control for pre-T2 Intel Macs via afanctl — presets, RPM slider, live thermals, keyboard shortcuts, zero new privilege surface" \
  --source . --push

# Branch model (one-time; R13): dev integrates, master ships
gh repo edit yadav-prakhar/omafan --default-branch dev
gh api -X PATCH repos/yadav-prakhar/omafan -f delete_branch_on_merge=true

# After pushing the final tree
gh repo edit yadav-prakhar/omafan --add-topic "omarchy-plugin,fan-control,mac,intel,smc"
```

## 4. Marketplace issue body (copy-paste verbatim)

The following is the exact text to paste into the
[plugin submission issue form](https://plugins.omarchy.org/publish.html) on
`plugins.omarchy.org`.

---

**Title:** omafan — Fan control for pre-T2 Intel Macs (via afanctl)

**Category:** Hardware

**Tags:** `fan-control`, `mac`, `intel`, `smc`, `afanctl`, `keyboard`

**Repository URL:** `https://github.com/yadav-prakhar/omafan`

**Description:**

> omafan is an Omarchy shell plugin that provides an interactive, keyboard-first
> control surface for the single fan of a pre-T2 Intel MacBook (MacBookPro14,1
> "A1708", `applesmc`) by driving the already-installed **afanctl** daemon.
>
> **What it does:**
>
> - **Bar widget** — live CPU temperature and fan RPM, tinted when the fan is
>   held off the firmware curve.
> - **Panel** — Auto / Floor / Low / Medium / High / Full presets, an RPM slider,
>   live status, degraded/offline banners with exact fix commands, and an
>   in-panel key map.
> - **Global keyboard shortcuts** — SUPER+ALT+{T,A,O,L,M,H,X,C} for panel
>   toggle, all six presets, and cycle, all verified free against the live
>   compositor bindings.
> - **CLI** — `omafan-ctl` for headless access (status, presets, preset, rpm,
>   release, cycle, doctor) with JSON output.
>
> **How it is different from the siblings:**
>
> - **Zero new privilege surface.** No udev rules, no sudoers entries, no root
>   helpers. Reuses afanctl's existing polkit rule.
> - **The fan is never left unowned.** Control is delegated to afanctl, whose
>   documented model fails toward the firmware (per-poll verify/re-assert, async
>   signal-safe AUTO restore on death, systemd watchdog).
> - **Keyboard-first.** Every panel action is reachable without a pointer.
> - **Truthful UI.** Presets are floors, not quieter-than-firmware modes. "Floor"
>   cannot stop the fan and says so. Degraded states are rendered from the
>   daemon's own fields.
>
> **Requirements:** Omarchy 4.0.0.alpha (Quattro), afanctl >= 0.1.0 installed
> and running. Pre-T2 Intel Mac with `applesmc`.
>
> **Install:**
> ```
> omarchy plugin add https://github.com/yadav-prakhar/omafan.git --enable
> ```
>
> **Uninstall:**
> ```
> bin/omafan-keybindings remove
> omarchy plugin remove io.github.yadav-prakhar.omafan
> ```
>
> **Licence:** GPL-3.0-only.

---

## 5. Post-submission notes

- Nothing in this repository submits the issue automatically; the repository owner
  submits it from their own GitHub account.
- After approval the operator should verify the listing appears at
  `https://plugins.omarchy.org/catalog.json` with the correct description.
- The `PREVIEW` file (optional `preview.png`) can be uploaded if the marketplace
  UI accepts a screenshot — not required.
