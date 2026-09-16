// tests/model.test.mjs — unit tests for Model.js (DESIGN.md §5).
//
// No dependencies: Model.js is read with node:fs and evaluated in a `new
// Function` sandbox, exactly as a QML `import "Model.js" as Model` would see the
// pure functions. The suite is table-driven and prints a final `PASS n / FAIL m`
// line, exiting non-zero on any failure so run-all.sh can gate on it.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "..", "Model.js"), "utf8");

const NAMES = [
  "presetsFor", "presetById", "presetRpm", "clampRpm", "snapRpm",
  "sliderPosFromRpm", "rpmFromSliderPos", "cyclePreset", "statusLabel",
  "modeTone", "degradedReason", "parseStatus", "progressFraction",
  "formatRpm", "formatTemp", "formatUptime", "isStateStale"
];

// T02b adds the two DESIGN.md §5.1 guard functions additively: the T02 list and
// its assertion stay as they were, and only the sandbox export grows.
const GUARD_NAMES = ["isUndercoolingHot", "undercoolingWarning"];
const ALL_NAMES = NAMES.concat(GUARD_NAMES);

let Model;
try {
  const body = source + "\nreturn {" + ALL_NAMES.join(",") + "};\n";
  Model = new Function(body)();
} catch (err) {
  console.error("FATAL: Model.js could not be evaluated: " + err.message);
  process.exit(1);
}

let pass = 0;
let fail = 0;
const failures = [];

function record(ok, label, detail) {
  if (ok) {
    pass++;
    return;
  }
  fail++;
  failures.push(label + (detail ? " :: " + detail : ""));
}

function eq(label, actual, expected) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  record(a === e, label, "expected " + e + ", got " + a);
}

function truthy(label, value) {
  record(Boolean(value), label, "expected truthy, got " + JSON.stringify(value));
}

function falsy(label, value) {
  record(!value, label, "expected falsy, got " + JSON.stringify(value));
}

function contains(label, haystack, needle) {
  const h = typeof haystack === "string" ? haystack : "";
  record(h.indexOf(needle) !== -1, label,
    "expected to contain " + JSON.stringify(needle) + ", got " + JSON.stringify(h));
}

function baseStatus() {
  return {
    schema: "omafan.status.v1",
    ok: true,
    afanctl: { path: "/usr/bin/afanctl", present: true, version: "0.1.0" },
    daemon: {
      running: true, mode: "observe", monitor_only: false,
      auto_restore_pending: false, uptime_s: 4920, polls: 2460,
      state_age_s: 1, state_stale: false, target_rpm: null
    },
    hardware: { fan_min_rpm: 1200, fan_max_rpm: 7200 },
    fan: { rpm: 1787, target_rpm: null, manual: false },
    thermal: { t_eff_c: 64.0, sensors: [{ label: "Package id 0", temp_c: 64.0 }] },
    hold: { active: false, preset: null, rpm: null },
    presets: [],
    recent_errors: [],
    warnings: []
  };
}

function withStatus(patch) {
  const status = baseStatus();
  for (const key of Object.keys(patch)) {
    if (["afanctl", "daemon", "hardware", "fan", "hold"].indexOf(key) !== -1) {
      status[key] = Object.assign({}, status[key], patch[key]);
    } else {
      status[key] = patch[key];
    }
  }
  return status;
}

const FIX_RESTART = "systemctl restart afanctl";
const FIX_CHECK = "omafan-ctl status";

// --- sandbox shape -------------------------------------------------------

record(NAMES.every((n) => typeof Model[n] === "function"),
  "Model.js exports all 17 DESIGN.md §5 functions as functions");
record(GUARD_NAMES.every((n) => typeof Model[n] === "function"),
  "Model.js exports both DESIGN.md §5.1 guard functions as functions");

// --- ES5-safety / purity of the source (the QML + Node dual use) ---------

eq("Model.js has no arrow functions", source.indexOf("=>"), -1);
eq("Model.js has no template literals", source.indexOf("`"), -1);
eq("Model.js does not call Object.assign", source.indexOf("Object.assign"), -1);
eq("Model.js does not import modules", /(^|\n)\s*import[\s(]/.test(source), false);
eq("Model.js does not require()", source.indexOf("require("), -1);
eq("Model.js does not sniff window", source.indexOf("window."), -1);
eq("Model.js does not sniff document", source.indexOf("document."), -1);
eq("Model.js does not sniff globalThis", source.indexOf("globalThis"), -1);
eq("Model.js has no QML pragma", source.indexOf(".pragma"), -1);
eq("Model.js has no TODO", source.indexOf("TODO"), -1);
record(source.endsWith("\n"), "Model.js ends with a newline");

// --- presetsFor / presetRpm ---------------------------------------------

const ladder = Model.presetsFor(1200, 7200);
eq("presetsFor returns six presets", ladder.length, 6);
eq("presetsFor order is auto/off/low/med/high/full",
  ladder.map((p) => p.id), ["auto", "off", "low", "med", "high", "full"]);
eq("presetsFor rpm ladder for (1200,7200) is 1200/2700/4200/5700/7200",
  ladder.map((p) => p.rpm), [null, 1200, 2700, 4200, 5700, 7200]);
eq("presetsFor kinds mark auto as release and the rest as hold",
  ladder.map((p) => p.kind), ["release", "hold", "hold", "hold", "hold", "hold"]);
eq("presetsFor labels match DESIGN.md §3",
  ladder.map((p) => p.label),
  ["Auto (firmware)", "Floor (hardware floor)", "Low", "Medium", "High", "Full"]);

const ladder2 = Model.presetsFor(2000, 6000);
eq("presetsFor scales the ladder to a different band",
  ladder2.map((p) => p.rpm), [null, 2000, 3000, 4000, 5000, 6000]);

eq("presetRpm('auto') is null", Model.presetRpm("auto", 1200, 7200), null);
eq("presetRpm('off') is the hardware floor", Model.presetRpm("off", 1200, 7200), 1200);
eq("presetRpm('low')", Model.presetRpm("low", 1200, 7200), 2700);
eq("presetRpm('med')", Model.presetRpm("med", 1200, 7200), 4200);
eq("presetRpm('high')", Model.presetRpm("high", 1200, 7200), 5700);
eq("presetRpm('full') is the hardware ceiling", Model.presetRpm("full", 1200, 7200), 7200);
eq("presetRpm('bogus') is null", Model.presetRpm("bogus", 1200, 7200), null);

// --- presetById ----------------------------------------------------------

eq("presetById finds med", Model.presetById(ladder, "med").rpm, 4200);
eq("presetById returns null for an unknown id", Model.presetById(ladder, "nope"), null);
eq("presetById returns null for an empty list", Model.presetById([], "med"), null);

// --- clampRpm ------------------------------------------------------------

eq("clampRpm below min pins to min", Model.clampRpm(0, 1200, 7200), 1200);
eq("clampRpm above max pins to max", Model.clampRpm(99999, 1200, 7200), 7200);
eq("clampRpm keeps an in-range value", Model.clampRpm(4200, 1200, 7200), 4200);
eq("clampRpm at min", Model.clampRpm(1200, 1200, 7200), 1200);
eq("clampRpm at max", Model.clampRpm(7200, 1200, 7200), 7200);
eq("clampRpm treats a missing value as min", Model.clampRpm(undefined, 1200, 7200), 1200);

// --- snapRpm -------------------------------------------------------------

eq("snapRpm rounds down to the 100 rpm grid", Model.snapRpm(4249, 1200, 7200, 100), 4200);
eq("snapRpm rounds up to the 100 rpm grid", Model.snapRpm(4250, 1200, 7200, 100), 4300);
eq("snapRpm below min pins to min", Model.snapRpm(500, 1200, 7200, 100), 1200);
eq("snapRpm above max pins to max", Model.snapRpm(99999, 1200, 7200, 100), 7200);
eq("snapRpm with a non-dividing step lands on the grid",
  Model.snapRpm(6600, 1200, 7000, 1000), 6200);
eq("snapRpm with a non-dividing step clamps to fan_max",
  Model.snapRpm(6900, 1200, 7000, 1000), 7000);
eq("snapRpm with step <= 0 degrades to plain clamp",
  Model.snapRpm(4444, 1200, 7200, 0), 4444);

// --- slider <-> rpm ------------------------------------------------------

eq("sliderPosFromRpm at min is 0", Model.sliderPosFromRpm(1200, 1200, 7200), 0);
eq("sliderPosFromRpm at max is 1", Model.sliderPosFromRpm(7200, 1200, 7200), 1);
eq("sliderPosFromRpm at mid is 0.5", Model.sliderPosFromRpm(4200, 1200, 7200), 0.5);
eq("sliderPosFromRpm of a missing rpm is 0", Model.sliderPosFromRpm(undefined, 1200, 7200), 0);
eq("sliderPosFromRpm of a degenerate band is 0",
  Model.sliderPosFromRpm(1200, 1200, 1200), 0);
eq("rpmFromSliderPos at 0 is min", Model.rpmFromSliderPos(0, 1200, 7200, 100), 1200);
eq("rpmFromSliderPos at 1 is max", Model.rpmFromSliderPos(1, 1200, 7200, 100), 7200);
eq("rpmFromSliderPos at 0.5 is med", Model.rpmFromSliderPos(0.5, 1200, 7200, 100), 4200);
eq("rpmFromSliderPos snaps on a non-dividing step",
  Model.rpmFromSliderPos(0.5, 1200, 7000, 1000), 4200);

// --- cyclePreset ---------------------------------------------------------

const forward = { auto: "off", off: "low", low: "med", med: "high", high: "full", full: "auto" };
const backward = { auto: "full", off: "auto", low: "off", med: "low", high: "med", full: "high" };
for (const id of ["auto", "off", "low", "med", "high", "full"]) {
  eq("cyclePreset forward from " + id, Model.cyclePreset(id, 1), forward[id]);
  eq("cyclePreset backward from " + id, Model.cyclePreset(id, -1), backward[id]);
}
eq("cyclePreset wraps forward at the end", Model.cyclePreset("full", 1), "auto");
eq("cyclePreset wraps backward at the start", Model.cyclePreset("auto", -1), "full");
eq("cyclePreset from an unknown id goes to auto", Model.cyclePreset("bogus", 1), "auto");
eq("cyclePreset from an unknown id backwards goes to full", Model.cyclePreset("bogus", -1), "full");

// --- statusLabel / modeTone ---------------------------------------------

eq("statusLabel offline for no status", Model.statusLabel(null), "Offline");
eq("statusLabel reports a hold with the rpm",
  Model.statusLabel(withStatus({
    daemon: { mode: "hold" }, fan: { rpm: 4200, target_rpm: 4200 },
    hold: { active: true, preset: "med", rpm: 4200 }
  })), "Holding 4,200 rpm");
eq("statusLabel reports firmware auto", Model.statusLabel(withStatus({})), "Firmware auto");
eq("statusLabel reports monitor only",
  Model.statusLabel(withStatus({ daemon: { monitor_only: true } })), "Monitor only");
eq("statusLabel reports a stopped daemon",
  Model.statusLabel(withStatus({ daemon: { running: false } })), "Daemon stopped");
eq("statusLabel reports a missing afanctl",
  Model.statusLabel(withStatus({ afanctl: { present: false } })), "afanctl missing");

eq("modeTone auto for a healthy observe daemon", Model.modeTone(withStatus({})), "auto");
eq("modeTone hold for a hold daemon",
  Model.modeTone(withStatus({ daemon: { mode: "hold" } })), "hold");
eq("modeTone degraded for monitor_only",
  Model.modeTone(withStatus({ daemon: { monitor_only: true } })), "degraded");
eq("modeTone degraded for auto_restore_pending",
  Model.modeTone(withStatus({ daemon: { auto_restore_pending: true } })), "degraded");
eq("modeTone degraded for a stale state",
  Model.modeTone(withStatus({ daemon: { state_stale: true } })), "degraded");
eq("modeTone offline for a stopped daemon",
  Model.modeTone(withStatus({ daemon: { running: false } })), "offline");
eq("modeTone offline for an error document", Model.modeTone({ ok: false }), "offline");

// --- degradedReason ------------------------------------------------------

eq("degradedReason is null when healthy", Model.degradedReason(withStatus({})), null);
contains("degradedReason monitor_only names the fix",
  Model.degradedReason(withStatus({ daemon: { monitor_only: true } })), FIX_RESTART);
contains("degradedReason auto_restore_pending names the fix",
  Model.degradedReason(withStatus({ daemon: { auto_restore_pending: true } })), FIX_CHECK);
contains("degradedReason stale state names the fix",
  Model.degradedReason(withStatus({ daemon: { state_stale: true } })), FIX_RESTART);
contains("degradedReason stopped daemon names the fix",
  Model.degradedReason(withStatus({ daemon: { running: false } })), "systemctl restart afanctl");
contains("degradedReason missing afanctl names the fix",
  Model.degradedReason(withStatus({ afanctl: { present: false } })), "install afanctl");
contains("degradedReason unavailable state names the fix",
  Model.degradedReason({ ok: false }), "systemctl restart afanctl");

// --- parseStatus ---------------------------------------------------------

const good = Model.parseStatus(JSON.stringify(baseStatus()));
eq("parseStatus accepts a valid status document", good.ok, true);
eq("parseStatus keeps the schema", good.status.schema, "omafan.status.v1");
eq("parseStatus keeps daemon.mode", good.status.daemon.mode, "observe");
const notJson = Model.parseStatus("afanctl: command not found");
eq("parseStatus rejects non-JSON", notJson.ok, false);
contains("parseStatus says why non-JSON failed", notJson.error, "JSON");
const wrong = Model.parseStatus(JSON.stringify({ schema: "omafan.other.v1" }));
eq("parseStatus rejects the wrong schema", wrong.ok, false);
contains("parseStatus names the unexpected schema", wrong.error, "omafan.other.v1");
eq("parseStatus rejects a JSON array", Model.parseStatus("[1,2,3]").ok, false);
eq("parseStatus rejects an empty string", Model.parseStatus("   ").ok, false);

// --- progressFraction ----------------------------------------------------

eq("progressFraction at min is 0", Model.progressFraction(withStatus({ fan: { rpm: 1200 } })), 0);
eq("progressFraction at max is 1", Model.progressFraction(withStatus({ fan: { rpm: 7200 } })), 1);
eq("progressFraction at mid is 0.5",
  Model.progressFraction(withStatus({ fan: { rpm: 4200 } })), 0.5);
eq("progressFraction with no status is 0", Model.progressFraction(undefined), 0);
eq("progressFraction with no fan reading is 0",
  Model.progressFraction(withStatus({ fan: { rpm: undefined } })), 0);
eq("progressFraction clamps an over-max reading to 1",
  Model.progressFraction(withStatus({ fan: { rpm: 9000 } })), 1);
eq("progressFraction for a degenerate band is 0",
  Model.progressFraction(withStatus({ hardware: { fan_min_rpm: 1200, fan_max_rpm: 1200 } })), 0);

// --- formatters ----------------------------------------------------------

eq("formatRpm groups thousands", Model.formatRpm(4200), "4,200 rpm");
eq("formatRpm groups 1200", Model.formatRpm(1200), "1,200 rpm");
eq("formatRpm groups 7200", Model.formatRpm(7200), "7,200 rpm");
eq("formatRpm leaves three digits alone", Model.formatRpm(999), "999 rpm");
eq("formatRpm handles zero", Model.formatRpm(0), "0 rpm");
eq("formatRpm groups millions", Model.formatRpm(1234567), "1,234,567 rpm");
eq("formatRpm renders a missing value as an em dash", Model.formatRpm(null), "—");

eq("formatTemp renders a whole degree", Model.formatTemp(64), "64 °C");
eq("formatTemp renders a half degree", Model.formatTemp(64.5), "64.5 °C");
eq("formatTemp rounds to one decimal", Model.formatTemp(64.04), "64 °C");
eq("formatTemp renders a missing value as an em dash", Model.formatTemp(undefined), "—");

eq("formatUptime seconds", Model.formatUptime(45), "45 s");
eq("formatUptime hours and minutes", Model.formatUptime(4920), "1 h 22 m");
eq("formatUptime whole hours", Model.formatUptime(3600), "1 h");
eq("formatUptime zero", Model.formatUptime(0), "0 s");
eq("formatUptime whole minutes", Model.formatUptime(120), "2 m");
eq("formatUptime days", Model.formatUptime(90000), "1 d 1 h");

// --- isStateStale --------------------------------------------------------

eq("isStateStale(4) is false", Model.isStateStale(4), false);
eq("isStateStale(5) is false (the 5 s floor is not exceeded)", Model.isStateStale(5), false);
eq("isStateStale(6) is true", Model.isStateStale(6), true);
eq("isStateStale(0) is false", Model.isStateStale(0), false);
eq("isStateStale(undefined) is true (refuse writes on an unread age)",
  Model.isStateStale(undefined), true);

// --- undercooling guard (DESIGN.md §5.1, T02b) ---------------------------

function guardStatus(temp, current) {
  return withStatus({ thermal: { t_eff_c: temp }, fan: { rpm: current } });
}

eq("isUndercoolingHot is false on a cold machine",
  Model.isUndercoolingHot(guardStatus(64, 4794), 2700), false);
eq("isUndercoolingHot is true at exactly 80 °C with a lower target",
  Model.isUndercoolingHot(guardStatus(80, 4794), 2700), true);
eq("isUndercoolingHot is false at 79 °C",
  Model.isUndercoolingHot(guardStatus(79, 4794), 2700), false);
eq("isUndercoolingHot is false when the target equals the current rpm",
  Model.isUndercoolingHot(guardStatus(97, 4200), 4200), false);
eq("isUndercoolingHot is false when the target is above the current rpm",
  Model.isUndercoolingHot(guardStatus(97, 4200), 5700), false);
eq("isUndercoolingHot is false for auto (null target)",
  Model.isUndercoolingHot(guardStatus(97, 4794), null), false);
eq("isUndercoolingHot is false for a null status",
  Model.isUndercoolingHot(null, 2700), false);
eq("isUndercoolingHot is false for a shapeless status",
  Model.isUndercoolingHot({}, 2700), false);
eq("isUndercoolingHot is false when the temperature is unreadable",
  Model.isUndercoolingHot(guardStatus(undefined, 4794), 2700), false);
eq("isUndercoolingHot is false when the fan rpm is unreadable",
  Model.isUndercoolingHot(guardStatus(97, undefined), 2700), false);
eq("isUndercoolingHot is false for a non-numeric target",
  Model.isUndercoolingHot(guardStatus(97, 4794), "abc"), false);

eq("undercoolingWarning is null when the machine is not undercooling",
  Model.undercoolingWarning(guardStatus(64, 4794), 2700), null);
eq("undercoolingWarning is null for auto",
  Model.undercoolingWarning(guardStatus(97, 4794), null), null);
eq("undercoolingWarning is null for a null status",
  Model.undercoolingWarning(null, 2700), null);

const warning = Model.undercoolingWarning(guardStatus(97, 4794), 2700);
truthy("undercoolingWarning returns a non-empty string when undercooling",
  typeof warning === "string" && warning.length > 0);
contains("undercoolingWarning names the temperature", warning, "97 °C");
contains("undercoolingWarning names the current rpm", warning, "4,794 rpm");
contains("undercoolingWarning names the requested rpm", warning, "2,700 rpm");
contains("undercoolingWarning says the request is below the curve", warning, "below");
contains("undercoolingWarning names the nearest preset at or above the fan",
  warning, "High (5,700 rpm)");
contains("undercoolingWarning tells the operator how to override", warning, "10 s");
eq("undercoolingWarning is a single sentence",
  (warning.match(/[.!?](\s|$)/g) || []).length, 1);
contains("undercoolingWarning falls back to Auto above the ladder ceiling",
  Model.undercoolingWarning(guardStatus(97, 9000), 1200), "Auto (firmware)");

// --- summary -------------------------------------------------------------

if (fail > 0) {
  for (const line of failures) console.error("FAIL " + line);
}
console.log("PASS " + pass + " / FAIL " + fail);
process.exit(fail > 0 ? 1 : 0);
