## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Evidence

<!-- The commands you ran and what they printed. "Tests pass" is not evidence. -->

```text
$ bash tests/run-all.sh
...
```

- [ ] `bash tests/run-all.sh` is green (paste the summary line)
- [ ] `omarchy plugin validate .` exits 0
- [ ] `bash -n bin/omafan-ctl bin/omafan-keybindings` is clean
- [ ] live check done when the UI changed (working tree copied into `~/.config/omarchy/plugins/`, then `omarchy-restart-shell` if the shell kept stale QML)

## Safety checklist

- [ ] No new privilege: no udev/polkit/sudoers entry, no root helper, no `/sys` write
- [ ] Reads still do not call `pkexec`; the privileged argv is unchanged (`[runner, /usr/bin/afanctl, verb, args]`)
- [ ] Nothing in the gate touches hardware, `/run/afanctl`, the real `$HOME`, or the network
- [ ] If fan state was touched while testing, it was released afterwards (`omafan-ctl status --human` shows `mode: observe, manual: false`)

## Contract and docs

- [ ] `DESIGN.md` is unchanged — **or** a `DEVIATIONS.md` entry is included and the ruling id is in the commit body
- [ ] Every mirror of a changed constant was updated (docs, README, PRD, tests)
- [ ] `CHANGELOG.md` has an `Unreleased` entry for user-visible changes
- [ ] For work on the `dev` branch: the feature's `worknotes/<slug>/` folder is
      updated — `LOG.md` with the evidence above, `SUMMARY.md` when it closes —
      or N/A
- [ ] Screenshots in the diff show the current build

## Notes for the reviewer

<!-- Anything you are unsure about, or deliberately left out of scope. -->
