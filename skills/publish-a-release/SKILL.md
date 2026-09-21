---
name: publish-a-release
description: Use when cutting a version of omafan, syncing the shipped branch, updating the marketplace listing, or refreshing the wiki after a release.
---

# Publish a release

Work lands on `dev`. `master` is the shipped branch and is **never merged into**:
a release copies an allowlist of shipped paths from `dev` onto `master` as one
commit, then tags it (step 3). `omarchy plugin add` clones the whole repository
into a user's `~/.config/omarchy/plugins/<id>`, so a merge would put
`worknotes/`, `orchestration/`, `skills/`, `PLAN.md` and every `AGENTS.md` inside
a stranger's installation, where their coding agent can read and act on it —
`DEVIATIONS.md` R11 is the guarantee, R13 is this mechanism.

## 1. Land everything first

On `dev`:

```sh
bash tests/run-all.sh          # every suite green
omarchy plugin validate .      # exits 0
git status --short             # clean: the release commit contains only the bump
```

## 2. Bump the version — five places, not one

| File | What to change |
|---|---|
| `manifest.json` | `"version"` |
| `bin/omafan-ctl` | `OMAFAN_CTL_VERSION` **and** the usage header line `omafan-ctl X.Y.Z - …` |
| `CHANGELOG.md` | move `Unreleased` content under `## [X.Y.Z] - YYYY-MM-DD`, add the link reference at the bottom |
| `tests/manifest.test.sh` | the `eq "version" … "X.Y.Z"` assertion |
| `tests/ctl.test.sh` | the `assert_eq "omafan-ctl X.Y.Z" …` assertion |

Miss one and the gate fails on a clean tree — the version is asserted, on
purpose. Then re-run `bash tests/run-all.sh`.

> [!NOTE]
> `manifest.json` is the operator-visible version; the CLI reports its own copy.
> If they disagree, a reviewer will trust the wrong one.

Commit the bump on `dev` like any other change:

```sh
git commit -m "release: vX.Y.Z

<one-paragraph summary — the CHANGELOG section is the detail>"
```

Release notes are the CHANGELOG section; do not write a second, different story.

## 3. Sync it onto `master`, then tag

[`sync-master.sh`](sync-master.sh) does the whole sync. It works in a throwaway
worktree, so your checkout is never touched, and it writes nothing without
`--commit`:

```sh
skills/publish-a-release/sync-master.sh --from dev              # review the diff
skills/publish-a-release/sync-master.sh --from dev --full-diff   # the whole diff
skills/publish-a-release/sync-master.sh --from dev --commit --tag vX.Y.Z
```

Read the diff before you pass `--commit`. It should contain shipped files only —
if a `worknotes/` or `AGENTS.md` path appears, stop: the script refuses to write
it, and that refusal is a bug report about the lists, not something to work
around.

Then prove the shipped tree, and push:

```sh
bash tests/branch-model.test.sh          # master carries no development material
git push origin master --follow-tags
git push origin dev
```

What the script does, in order: copies each entry of `OMAFAN_SHIPPED_PATHS` from
`dev`, replacing it outright so a file deleted on `dev` disappears from `master`;
prunes every `OMAFAN_DEV_PATHS` entry the allowlist swept up (`bin/AGENTS.md`,
`tests/AGENTS.md` and `docs/agents/` all sit *inside* allowlisted directories);
refuses if any denylisted path survived; refuses if the result has no
`manifest.json`; names the paths carried over untouched; prints the diff; and only
then commits and tags. Running it twice reports `already in sync` and exits 0.

Both lists live in [`tests/lib/shipped-paths.sh`](../../tests/lib/shipped-paths.sh)
— one home, read by this script, `.githooks/pre-commit`, the `branch-model` gate
suite and `.github/workflows/ci.yml`. Changing what ships means changing that
file and nothing else.

> [!NOTE]
> The sibling project `afanctl` has **no** equivalent constraint — nothing clones
> it into a user's config — so its release is an ordinary `dev` → `master` merge.
> Do not carry this script's approach over to it.

## 4. Marketplace listing

`docs/PUBLISHING.md` holds the submission package: the pre-submit checklist, the
`gh` commands, and the issue body to paste into
[plugins.omarchy.org](https://plugins.omarchy.org). The **operator** submits it;
an agent should prepare the text and say so, not post it.

Re-check the two checklist items a release can break:

- `README.md` still covers what it is, requirements, install, usage, keyboard
  shortcuts, safety model, uninstall.
- `preview.png` shows the current build. If the UI changed, re-capture it (see the
  `capture-docs-screenshots` skill) — the old chip label `Off (floor)` is a real
  example of a screenshot that outlived its UI.

## 5. Refresh the wiki

The wiki is a separate repository, `https://github.com/yadav-prakhar/omafan.wiki`:

```sh
cd ~/Work/tries/omafan-wiki
git pull
# update version strings, the CLI/output samples and any changed UI image, then:
git commit -am "docs: sync with vX.Y.Z"
git push
```

Keep its pages honest: screenshots are dated and attributed to the build they came
from, and anything you could not capture is listed as not captured, with the
reason.

## 6. After the release

- Verify the push: `git ls-remote --tags origin | grep vX.Y.Z`.
- If the listing is live, check `https://plugins.omarchy.org/catalog.json`
  contains the new description and version.
- Record the release in the feature's `worknotes/<slug>/LOG.md` and close it with
  a `SUMMARY.md` line (`worknotes/README.md`). Record it in
  `orchestration/LEDGER.md` (newest first) only if you are working from that
  build-era history, so the flight recorder stays complete.
