---
name: live-verify-in-the-shell
description: Use when a change must be checked against a running Omarchy session (QML, panel, bar widget, IPC, chords), or when the live UI does not reflect the files you just edited.
---

# Verify a change in the live shell

The gate cannot see the UI. Anything that touches `BarWidget.qml`, `Panel.qml`,
`KeyboardHelp.qml`, `manifest.json` or the IPC surface needs a live check on a
machine that has Omarchy, afanctl and the plugin installed.

## Put the working tree into the shell

The shell loads plugins only from `~/.config/omarchy/plugins/<id>/`, so the
working tree must be copied there:

```sh
orchestration/live-install.sh install    # backups shell.json -> orchestration/backups/, rsyncs, enables, rescans
orchestration/live-install.sh verify     # registry + IPC state + shell log + bar layout entry
orchestration/live-install.sh remove     # takes it out of the shell
orchestration/live-install.sh revert     # restores the backed-up shell.json
```

`install` preserves relative paths and excludes `orchestration/logs`; it also
runs `omarchy plugin validate` before enabling. Read the `verify` output — it
prints the plugin registry line, the IPC `state` document, and any shell-log lines
mentioning omafan or an error.

## The stale-QML trap

Saving a file under the plugin directory normally hot-reloads the plugin, and
`omarchy-shell shell rescanPlugins` forces a re-walk — but on this machine a
rescan left the **old** `Panel.qml` compiled and rendered while `Model.js` had
already reloaded. The proof was a chip label from the previous build on screen
while the IPC state reported the new one.

When the rendered UI disagrees with the files:

```sh
omarchy-shell shell rescanPlugins        # usually enough
omarchy-restart-shell                    # the reliable fallback: restarts the shell, keeps apps
for i in $(seq 1 20); do sleep 1; omarchy-shell shell ping >/dev/null 2>&1 && echo up && break; done
```

Then confirm what is actually running, not what you copied:

```sh
omarchy-shell omafan state               # the status document the panel holds, verbatim
omarchy plugin list --json | jq -c '.[] | select(.id|test("omafan"))'
qs log -p /usr/share/omarchy/shell --tail 300 2>/dev/null | grep -iE "omafan|error" | tail -20
```

## IPC surface to poke

```sh
omarchy-shell omafan open | close | toggle
omarchy-shell omafan refresh
omarchy-shell omafan preset med          # returns "ok: med 4200 rpm" or "error: …"
omarchy-shell omafan rpm 3000
omarchy-shell omafan release
omarchy-shell omafan state
```

Read verbs are safe to call any time. `preset`, `rpm` and `release` are **writes**:
they go through `pkexec` to the real fan. Do not call them as a smoke test on
someone else's machine, and never call them unattended on a hot laptop.

## Verify without touching the fan

`bin/omafan-ctl` is the same surface as the panel and is where to check behaviour:

```sh
OMAFAN_DIR=~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan
"$OMAFAN_DIR/bin/omafan-ctl" doctor --human     # 12 checks, names the fix per FAIL
"$OMAFAN_DIR/bin/omafan-ctl" status --human     # daemon mode, fan rpm, t_eff, band
"$OMAFAN_DIR/bin/omafan-ctl" presets --human    # the ladder + slider band
"$OMAFAN_DIR/bin/omafan-ctl" preset high --dry-run   # prints the argv, writes nothing
```

`--dry-run` is the honest way to show a write path without taking it. `status`
and `presets` are read-only; `doctor` can take ~30 ms via `pkexec` for its
`pkexec_write_path` probe but changes nothing.

## Ending clean

- Leave the fan where you found it: check `status --human` for
  `mode: observe, manual: false`. If you (or the user) held the fan, `release`.
- Remove test windows and any temporary plugin copies. If you changed a bar
  setting for a screenshot, put it back:
  `omarchy bar set io.github.yadav-prakhar.omafan show temp`.
- Report exactly which commands wrote what. A live check that quietly held the
  fan is a safety bug, not a test.
