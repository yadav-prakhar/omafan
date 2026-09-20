---
name: publish-a-release
description: Use when cutting a version of omafan, updating the marketplace listing, or refreshing the wiki after a release.
---

# Publish a release

## 1. Land everything first

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

## 3. Commit and tag

```sh
git commit -m "release: vX.Y.Z

<one-paragraph summary — the CHANGELOG section is the detail>"
git tag -a vX.Y.Z -m "omafan vX.Y.Z"
git push origin master --follow-tags
```

Release notes are the CHANGELOG section; do not write a second, different story.

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
