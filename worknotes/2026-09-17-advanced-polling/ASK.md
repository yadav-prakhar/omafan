---
feature: advanced-polling
status: done
branch: dev
opened: 2026-09-17
updated: 2026-09-17
related:
  - 2026-09-17-advanced-polling/PLAN.md
---

# The ask (verbatim)

The operator's own note that opened this work, kept verbatim so the
requirements of record are not a paraphrase. It pre-dates `worknotes/` and was
held outside the repository until 2026-09-20; `PRD.md` D-list refers to it.

*Migrated from the pre-`worknotes/` archive note `prompt.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

### ask

- i need you to update the root agents.md file with info that all the work must be noted in "/home/prakhar/Documents/Default/Workspace/omarchy plugin development/omafan" obsidian notes for this repo in a well arranged manner in subfolders: done, logs, plans, reviews.  If you think there is some other way to organize the folders for all the work that is going to be done for this plugin, then you can create respective folders and arrange the files in that order.
- when preset is set to auto, the rpm slider continues to show the rpm that was last set manually. need to reset it to base value to indicate the custom value is not in effect. 
- add polling interval control in an advanced toggle:
  - auto: current default
  - custom: takes input from user. unit is in seconds
  - if there's any change needed to be done in afanctl for this, then do so and write up in afanctl obsidian folder.

### references:
- https://github.com/yadav-prakhar/afanctl
- github.com/benekuehn/omarchy.mac-fans
- github.com/gaul/mbpfan
- plugin development guide: https://plugins.omarchy.org/develop.html
- publishing guide: https://plugins.omarchy.org/publish.html
- submit plugin link: https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml
