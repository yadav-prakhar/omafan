---
name: Bug report
about: Something behaves differently from the documentation
title: ""
labels: bug
assignees: ""
---

<!--
Before filing: run `bin/omafan-ctl doctor --human`. Most failures name their own
fix, and the fix is usually what the report needs to say.
Redact absolute paths containing your username, and serials or tokens.
-->

## What happened

<!-- What you did, what you expected, what happened instead. -->

## Hardware and versions

| | |
|---|---|
| Mac model | <!-- `sysctl hw.model` or About This Mac --> |
| Omarchy | <!-- `cat /usr/share/omarchy/version` --> |
| afanctl | <!-- `afanctl --version` --> |
| omafan | <!-- `jq -r .version ~/.config/omarchy/plugins/io.github.yadav-prakhar.omafan/manifest.json` --> |

## Evidence

```text
$ bin/omafan-ctl doctor --human
<paste the 12 check lines>

$ bin/omafan-ctl status --human
<paste output>
```

## Fan state

- [ ] the fan is in firmware auto right now (`status --human` shows `mode: observe, manual: false`)
- [ ] a hold is active — the rpm I asked for and the rpm reported: <!-- e.g. asked 4200, reported 4210 -->

## Anything else

<!-- Panel/bar screenshot, the exact exit code, whether it reproduces after
`omarchy-restart-shell`, and whether the fan was hotter than usual. -->
