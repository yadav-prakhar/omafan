// Model.js — pure logic for omafan (DESIGN.md §5).
//
// No QtQuick/Quickshell modules, no QML types, no I/O and no side effects: the
// same file is loaded by the panel and source-evaluated by
// tests/model.test.mjs, so everything here is ES5-safe (var/function only) and
// carries no QML pragma — the harness evaluates the source inside new Function
// as plain JavaScript.

var PRESET_ORDER = ["auto", "off", "low", "med", "high", "full"];

var PRESET_LABELS = {
  auto: "Auto (firmware)",
  off: "Floor (hardware floor)",
  low: "Low",
  med: "Medium",
  high: "High",
  full: "Full"
};

var STATUS_SCHEMA = "omafan.status.v1";

// Schema negotiation (omafan#4). A schema id is "<family>.v<major>". Each side
// declares what it can emit/understand and the highest version both understand
// is used. An unknown NEWER version is tolerated — the recognised fields still
// render, with one quiet notice — while an unknown OLDER version is refused.
// These helpers are pure and ES5-only so the Node harness exercises the whole
// matrix with no QML and no daemon; bin/omafan-ctl mirrors the same rule in one
// bash helper because it cannot import this file (as the preset ladder is).
var OMAFAN_STATUS_FAMILY = "omafan.status";
var OMAFAN_STATUS_SUPPORTED = [STATUS_SCHEMA];

// parseSchemaId("afanctl.status.v2") -> {family:"afanctl.status",version:2},
// or null for anything that is not exactly "<family>.v<digits>".
function parseSchemaId(id) {
  if (typeof id !== "string") return null;
  var match = /^(.+)\.v([0-9]+)$/.exec(id);
  if (!match) return null;
  var family = match[1];
  var version = Number(match[2]);
  if (!family || !isFinite(version)) return null;
  return { family: family, version: version };
}

// Coerce a schema list into an array of strings; a bare string is one id.
function schemaIds(value) {
  if (typeof value === "string") return [value];
  if (value && typeof value.length === "number") {
    var out = [];
    for (var i = 0; i < value.length; i++) {
      if (typeof value[i] === "string") out.push(value[i]);
    }
    return out;
  }
  return [];
}

function schemaHasVersion(list, family, version) {
  for (var i = 0; i < list.length; i++) {
    var parsed = parseSchemaId(list[i]);
    if (parsed && parsed.family === family && parsed.version === version) return true;
  }
  return false;
}

// selectSchema(family, advertised, supported) -> {status, schema, version}:
//   match    the highest version present in both lists
//   newer    no mutual version and the highest advertised is not below the
//            supported minimum (an unknown newer version: safe to degrade)
//   older    no mutual version and the highest advertised is below the minimum
//   unknown  nothing parseable in this family (missing or malformed schema)
function selectSchema(family, advertised, supported) {
  var ads = schemaIds(advertised);
  var sups = schemaIds(supported);
  var i, parsed;
  var adVersion = null, adId = null;
  var supMin = null;
  var matchVersion = null, matchId = null;
  for (i = 0; i < ads.length; i++) {
    parsed = parseSchemaId(ads[i]);
    if (!parsed || parsed.family !== family) continue;
    if (adVersion === null || parsed.version > adVersion) {
      adVersion = parsed.version;
      adId = ads[i];
    }
  }
  for (i = 0; i < sups.length; i++) {
    parsed = parseSchemaId(sups[i]);
    if (!parsed || parsed.family !== family) continue;
    if (supMin === null || parsed.version < supMin) supMin = parsed.version;
  }
  if (adVersion === null || supMin === null) {
    return { status: "unknown", schema: null, version: null };
  }
  for (i = 0; i < ads.length; i++) {
    parsed = parseSchemaId(ads[i]);
    if (!parsed || parsed.family !== family) continue;
    if (schemaHasVersion(sups, family, parsed.version)) {
      if (matchVersion === null || parsed.version > matchVersion) {
        matchVersion = parsed.version;
        matchId = ads[i];
      }
    }
  }
  if (matchVersion !== null) {
    return { status: "match", schema: matchId, version: matchVersion };
  }
  if (adVersion < supMin) {
    return { status: "older", schema: adId, version: adVersion };
  }
  return { status: "newer", schema: adId, version: adVersion };
}

// DESIGN.md §4.1 defines staleness as "exceeds max(5 s, 3 x poll interval)".
// This function receives only the age, so it applies the documented 5 s floor;
// a caller that knows its poll interval may choose a larger threshold.
var STALE_AFTER_S = 5;

// Coerce whatever QML hands us into a finite number. null/undefined/"" must not
// sail through as 0 via Number(), because a missing rpm is not "0 rpm".
function finite(value) {
  if (value === null || value === undefined || value === "") return NaN;
  var n = typeof value === "number" ? value : Number(value);
  return isFinite(n) ? n : NaN;
}

// Preset ladder of DESIGN.md §3: auto releases, every other preset holds an rpm
// derived from the live hardware band so the plugin travels to other pre-T2 Macs.
function presetRpm(id, minRpm, maxRpm) {
  if (id === "auto") return null;
  var lo = Math.round(finite(minRpm));
  var hi = Math.round(finite(maxRpm));
  if (!isFinite(lo) || !isFinite(hi) || hi < lo) return null;
  var span = hi - lo;
  if (id === "off") return lo;
  if (id === "low") return Math.round(lo + 0.25 * span);
  if (id === "med") return Math.round(lo + 0.5 * span);
  if (id === "high") return Math.round(lo + 0.75 * span);
  if (id === "full") return hi;
  return null;
}

function presetsFor(minRpm, maxRpm) {
  var out = [];
  for (var i = 0; i < PRESET_ORDER.length; i++) {
    var id = PRESET_ORDER[i];
    out.push({
      id: id,
      label: PRESET_LABELS[id],
      rpm: presetRpm(id, minRpm, maxRpm),
      kind: id === "auto" ? "release" : "hold"
    });
  }
  return out;
}

function presetById(list, id) {
  if (!list || !list.length) return null;
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].id === id) return list[i];
  }
  return null;
}

function clampRpm(rpm, minRpm, maxRpm) {
  var lo = finite(minRpm);
  var hi = finite(maxRpm);
  var v = finite(rpm);
  if (!isFinite(lo)) lo = 0;
  if (!isFinite(hi)) hi = lo;
  if (hi < lo) {
    var swap = lo;
    lo = hi;
    hi = swap;
  }
  if (!isFinite(v)) v = lo;
  if (v < lo) v = lo;
  if (v > hi) v = hi;
  return Math.round(v);
}

// Clamp, then pull onto the step grid anchored at fan_min (DESIGN.md §3), then
// clamp again: a step that does not divide the range leaves the top of the
// slider at fan_max, never above it.
function snapRpm(rpm, minRpm, maxRpm, stepRpm) {
  var v = clampRpm(rpm, minRpm, maxRpm);
  var step = finite(stepRpm);
  if (!isFinite(step) || step <= 0) return v;
  var base = finite(minRpm);
  if (!isFinite(base)) base = v;
  var snapped = Math.round((v - base) / step) * step + base;
  return clampRpm(snapped, minRpm, maxRpm);
}

function sliderPosFromRpm(rpm, minRpm, maxRpm) {
  var lo = finite(minRpm);
  var hi = finite(maxRpm);
  var v = finite(rpm);
  if (!isFinite(lo) || !isFinite(hi) || hi <= lo || !isFinite(v)) return 0;
  var pos = (v - lo) / (hi - lo);
  if (pos < 0) pos = 0;
  if (pos > 1) pos = 1;
  return pos;
}

function rpmFromSliderPos(pos, minRpm, maxRpm, step) {
  var lo = finite(minRpm);
  var hi = finite(maxRpm);
  var p = finite(pos);
  if (!isFinite(lo)) lo = 0;
  if (!isFinite(hi)) hi = lo;
  if (!isFinite(p)) p = 0;
  if (p < 0) p = 0;
  if (p > 1) p = 1;
  return snapRpm(lo + p * (hi - lo), lo, hi, step);
}

// dir ±1 walks the §3 order and wraps (auto -> off -> ... -> full -> auto). An
// unknown current id lands on auto going forward and full going backward.
function cyclePreset(currentId, dir) {
  var step = finite(dir) < 0 ? -1 : 1;
  var idx = -1;
  for (var i = 0; i < PRESET_ORDER.length; i++) {
    if (PRESET_ORDER[i] === currentId) {
      idx = i;
      break;
    }
  }
  if (idx < 0) idx = step < 0 ? 0 : -1;
  var n = PRESET_ORDER.length;
  return PRESET_ORDER[((idx + step) % n + n) % n];
}

function statusLabel(status) {
  if (!status || status.ok === false) return "Offline";
  var daemon = status.daemon || {};
  var afanctl = status.afanctl || {};
  if (afanctl.present === false) return "afanctl missing";
  if (daemon.running === false) return "Daemon stopped";
  if (daemon.monitor_only === true) return "Monitor only";
  if (daemon.auto_restore_pending === true) return "Returning to auto";
  if (daemon.state_stale === true) return "Status stale";
  if (daemon.mode === "hold") {
    var hold = status.hold || {};
    var rpm = hold.rpm !== null && hold.rpm !== undefined ? hold.rpm : daemon.target_rpm;
    return "Holding " + formatRpm(rpm);
  }
  return "Firmware auto";
}

// Four tones only (DESIGN.md §5): offline wins over degraded, degraded over
// hold, so a monitor-only / auto-restoring / stale daemon never shows as if it
// were holding normally.
function modeTone(status) {
  if (!status || status.ok === false) return "offline";
  var daemon = status.daemon || {};
  var afanctl = status.afanctl || {};
  if (afanctl.present === false || daemon.running === false) return "offline";
  if (daemon.monitor_only === true || daemon.auto_restore_pending === true ||
      daemon.state_stale === true) {
    return "degraded";
  }
  if (daemon.mode === "hold") return "hold";
  return "auto";
}

// Returns null when the daemon is healthy, else a human sentence naming both the
// problem and the fix (DESIGN.md §8: the panel shows the exact systemctl command).
function degradedReason(status) {
  if (!status || status.ok === false) {
    return "afanctl state is unavailable. Fix: systemctl restart afanctl";
  }
  var daemon = status.daemon || {};
  var afanctl = status.afanctl || {};
  if (afanctl.present === false) {
    return "afanctl is missing. Fix: install afanctl, then systemctl restart afanctl";
  }
  if (daemon.running === false) {
    return "The afanctl daemon is not running. Fix: systemctl restart afanctl";
  }
  if (daemon.monitor_only === true) {
    return "Daemon is monitor-only, so writes are refused. Fix: systemctl restart afanctl";
  }
  if (daemon.auto_restore_pending === true) {
    return "Daemon is returning the fan to firmware auto. Fix: check with omafan-ctl status";
  }
  if (daemon.state_stale === true) {
    return "The afanctl state is stale. Fix: systemctl restart afanctl";
  }
  return null;
}

function parseStatus(text) {
  if (typeof text !== "string" || text.replace(/\s+/g, "") === "") {
    return { ok: false, error: "status output is empty" };
  }
  var parsed;
  try {
    parsed = JSON.parse(text);
  } catch (err) {
    return { ok: false, error: "status output is not valid JSON" };
  }
  if (!parsed || typeof parsed !== "object" || typeof parsed.length === "number") {
    return { ok: false, error: "status output is not a JSON object" };
  }
  // The panel has no request channel, so the *emitted* schema governs: a newer
  // document is rendered with a notice even if it also advertises a version
  // this plugin understands (there is nothing to re-request from here).
  var picked = selectSchema(OMAFAN_STATUS_FAMILY, [parsed.schema], OMAFAN_STATUS_SUPPORTED);
  if (picked.status === "unknown") {
    return { ok: false, error: "unexpected status schema: " + String(parsed.schema) };
  }
  if (picked.status === "older") {
    return { ok: false, error: "status schema " + String(parsed.schema) +
      " is older than this plugin supports (" + OMAFAN_STATUS_SUPPORTED[0] +
      " required); update omafan" };
  }
  if (picked.status === "newer") {
    // The daemon is working, only some fields are unreadable: render what is
    // recognised and say so once, never a blank panel and never a hard error.
    return { ok: true, status: parsed,
      notice: "status schema " + picked.schema + " is newer than this plugin understands (" +
        OMAFAN_STATUS_SUPPORTED[0] + "); some fields may be missing. Fix: update the omafan plugin" };
  }
  return { ok: true, status: parsed };
}

// The single quiet notice for a schema the plugin does not fully understand:
// the first warnings[] entry that names a schema, or null. The CLI records the
// afanctl-schema notice there; the panel renders this one line, never a blank
// panel and never a hard error (omafan#4).
function statusNotice(status) {
  if (!status || status.ok === false) return null;
  var warnings = status.warnings;
  if (!warnings || !warnings.length) return null;
  for (var i = 0; i < warnings.length; i++) {
    if (typeof warnings[i] === "string" && warnings[i].indexOf("schema") !== -1) {
      return warnings[i];
    }
  }
  return null;
}

function progressFraction(status) {
  if (!status || status.ok === false) return 0;
  var hardware = status.hardware || {};
  var fan = status.fan || {};
  var lo = finite(hardware.fan_min_rpm);
  var hi = finite(hardware.fan_max_rpm);
  var v = finite(fan.rpm);
  if (!isFinite(lo) || !isFinite(hi) || hi <= lo || !isFinite(v)) return 0;
  var frac = (v - lo) / (hi - lo);
  if (frac < 0) frac = 0;
  if (frac > 1) frac = 1;
  return frac;
}

// Plain "," thousands separators, no locale (DESIGN.md §5). An unknown value
// renders as an em dash so the bar never claims a number it does not have.
function formatRpm(n) {
  var v = finite(n);
  if (!isFinite(v)) return "—";
  var text = String(Math.round(Math.abs(v)));
  var grouped = "";
  var count = 0;
  for (var i = text.length - 1; i >= 0; i--) {
    grouped = text.charAt(i) + grouped;
    count++;
    if (count % 3 === 0 && i > 0) grouped = "," + grouped;
  }
  return (v < 0 ? "-" : "") + grouped + " rpm";
}

function formatTemp(c) {
  var v = finite(c);
  if (!isFinite(v)) return "—";
  return String(Math.round(v * 10) / 10) + " °C";
}

function formatUptime(seconds) {
  var v = finite(seconds);
  if (!isFinite(v) || v < 0) return "—";
  var total = Math.floor(v);
  var days = Math.floor(total / 86400);
  var hours = Math.floor(total / 3600) % 24;
  var minutes = Math.floor(total / 60) % 60;
  var secs = total % 60;
  if (days > 0) return days + " d " + hours + " h";
  if (hours > 0) return minutes > 0 ? hours + " h " + minutes + " m" : hours + " h";
  if (minutes > 0) return secs > 0 ? minutes + " m " + secs + " s" : minutes + " m";
  return secs + " s";
}

// Unknown/negative ages count as stale: refusing a write is safer than trusting
// a timestamp we could not read (DESIGN.md §4.1, PRD F6).
function isStateStale(ageSeconds) {
  var v = finite(ageSeconds);
  if (!isFinite(v) || v < 0) return true;
  return v > STALE_AFTER_S;
}

// Advanced polling control (plan 2026-09-17 T3): how often omafan re-reads the
// daemon's status — never how often the daemon samples the SMC (afanctl's own
// [poll] interval_s is out of scope). Mode "auto" is exactly 2 s; mode
// "custom" uses poll_seconds in whole seconds 1-10.
var AUTO_POLL_SECONDS = 2;
var MIN_POLL_SECONDS = 1;
var MAX_POLL_SECONDS = 10;

// Mode math for Panel.qml pollSeconds. Anything but "custom" (auto, missing,
// unknown) is exactly AUTO_POLL_SECONDS, so an existing shell.json with a
// leftover nondefault poll_seconds keeps today's behaviour without touching
// anything. A custom value must be whole seconds: fractional or non-numeric
// input is ignored (falls back to AUTO_POLL_SECONDS); whole seconds outside
// 1-10 are clamped, never fatal.
function effectivePollSeconds(mode, pollSeconds) {
  if (mode !== "custom") return AUTO_POLL_SECONDS;
  var n = finite(pollSeconds);
  if (!isFinite(n) || Math.floor(n) !== n) return AUTO_POLL_SECONDS;
  if (n < MIN_POLL_SECONDS) return MIN_POLL_SECONDS;
  if (n > MAX_POLL_SECONDS) return MAX_POLL_SECONDS;
  return n;
}

// DESIGN.md §5.1: on a hot machine a preset can command less airflow than the
// firmware already delivers, so the first attempt must be confirmed. An
// unreadable temperature, rpm or target is treated as "not hot", never as
// "unsafe", so a missing sensor cannot deadlock the panel; this is why the
// numeric guards below return false rather than true.
function isUndercoolingHot(status, targetRpm) {
  if (!status || typeof status !== "object") return false;
  var thermal = status.thermal || {};
  var fan = status.fan || {};
  var temp = finite(thermal.t_eff_c);
  var current = finite(fan.rpm);
  var target = finite(targetRpm);
  if (!isFinite(temp) || !isFinite(current) || !isFinite(target)) return false;
  return temp >= 80 && target < current;
}

// The smallest airflow increase that still beats the firmware: the first preset
// in §3 order whose rpm reaches the fan's current speed. Past the ladder
// ceiling the only safe instruction left is the release preset, so say that
// rather than name a preset that would slow the fan down.
function undercoolingAlternative(status, currentRpm) {
  var hardware = (status && status.hardware) || {};
  var ladder = presetsFor(hardware.fan_min_rpm, hardware.fan_max_rpm);
  for (var i = 0; i < ladder.length; i++) {
    var preset = ladder[i];
    if (preset.rpm === null) continue;
    if (preset.rpm >= currentRpm) {
      return preset.label + " (" + formatRpm(preset.rpm) + ")";
    }
  }
  return "Auto (firmware)";
}

// One sentence carrying every fact needed to make an informed override: the
// temperature, what the fan is doing now, what was requested, why it is unsafe
// and what to pick instead (DESIGN.md §5.1). Null unless the guard fires.
function undercoolingWarning(status, targetRpm) {
  if (!isUndercoolingHot(status, targetRpm)) return null;
  var temp = finite(status.thermal.t_eff_c);
  var current = finite(status.fan.rpm);
  var requested = finite(targetRpm);
  var alternative = undercoolingAlternative(status, current);
  return "CPU " + formatTemp(temp) + ", fan " + formatRpm(current) +
    ": the requested " + formatRpm(requested) + " is below the firmware curve; " +
    "press Enter again within 10 s to override, or pick " + alternative +
    " or higher.";
}
