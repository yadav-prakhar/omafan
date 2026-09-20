
# Backlog — omafan roadmap

Migrated from the pre-`worknotes/` archive note `todos for omafan.md`
(archive path), 2026-09-20 — content unedited. The `Small work` and `Big work`
lists are the maintainer's roadmap; the trailing `Standup` section is non-omafan
scratch kept verbatim rather than dropped.

## standup

*Migrated from the pre-`worknotes/` archive note `todos for omafan.md` (archive path), 2026-09-20 — content unedited apart from heading level and link targets.*

upgrades to omafan:


## Small work
- [x] rename off → floor
- [x] add built-for-omarchy-plugin badge & also omarchy version support badge from: https://github.com/tcballard/omarchy-badges 
- [x] improve readme

---

## Big work


- [x] when preset is set to auto, the rpm slider continues to show the rpm that was last set manually. need to reset it to base value to indicate the custom value is not in effect. 
- [x] add polling interval control in an advanced toggle:
  - auto: current default
  - custom: takes input from user. unit is in seconds
  - if there's any change needed to be done in afanctl for this, then do so and write up in afanctl obsidian folder.
- [ ] add support for other fan ctl cli so they are a drop in replacement for the omafan
- [ ] after modular omafan panel which can adopt any fan control cli, add t2 mac fan support 
- [ ] add non-mac laptop fan control.





# standup

- continue to work on profile card widget ssr pure
- profile details widget is made ssr safe but need to make it ssr pure
- need to connect with Aakaah on a notification related item
- need to work on moveworks optimization, but not today.
