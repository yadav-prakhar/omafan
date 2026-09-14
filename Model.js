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
  off: "Off (hardware floor)",
  low: "Low",
  med: "Medium",
  high: "High",
  full: "Full"
};

var STATUS_SCHEMA = "omafan.status.v1";

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
  if (parsed.schema !== STATUS_SCHEMA) {
    return { ok: false, error: "unexpected status schema: " + String(parsed.schema) };
  }
  return { ok: true, status: parsed };
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
