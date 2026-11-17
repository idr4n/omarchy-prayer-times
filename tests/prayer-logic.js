#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const sourcePath = path.join(__dirname, "../PrayerLogic.js");
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\.pragma library\s*/, "");
const context = { Date, Math, Number, String, isFinite, isNaN };
vm.createContext(context);
vm.runInContext(source, context, { filename: sourcePath });

const times = [
  {
    name: "Fajr",
    label: "Fajr",
    time: "05:00",
    iso: "2026-08-29T05:00:00Z",
    isPrayer: true,
  },
  {
    name: "Sunrise",
    label: "Sunrise",
    time: "06:20",
    iso: "2026-08-29T06:20:00Z",
    isPrayer: false,
  },
  {
    name: "Dhuhr",
    label: "Dhuhr",
    time: "12:00",
    iso: "2026-08-29T12:00:00Z",
    isPrayer: true,
  },
];

const beforeDhuhr = context.deriveState(
  times,
  null,
  Date.parse("2026-08-29T11:54:30Z"),
);
assert.equal(beforeDhuhr.nextName, "Dhuhr");
assert.equal(beforeDhuhr.secondsToNext, 330);
assert.equal(beforeDhuhr.withinPre, true);
assert.equal(beforeDhuhr.withinFlash, true);
assert.equal(beforeDhuhr.countdownText, "6m");

const afterDhuhr = context.deriveState(
  times,
  {
    fajr: {
      name: "Fajr",
      label: "Fajr",
      time: "05:01",
      iso: "2026-08-30T05:01:00Z",
    },
  },
  Date.parse("2026-08-29T12:07:00Z"),
);
assert.equal(afterDhuhr.nextName, "Fajr");
assert.equal(afterDhuhr.currentName, "Dhuhr");
assert.equal(afterDhuhr.secondsSinceAdhan, 420);
assert.equal(afterDhuhr.withinElapsed, true);

const absoluteSettings = context.sanitizeSettings({
  textMode: "full-time",
  showIcon: false,
});
assert.equal(context.formatBarText(beforeDhuhr, absoluteSettings), "Dhuhr 12:00");

const relativeSettings = context.sanitizeSettings({
  textMode: "full-relative",
});
assert.equal(context.formatBarText(beforeDhuhr, relativeSettings), "Dhuhr in 6m");

const initialRelativeSettings = context.sanitizeSettings({
  textMode: "initial-relative",
});
assert.equal(context.formatBarText(beforeDhuhr, initialRelativeSettings), "D in 6m");

const atDhuhr = context.deriveState(
  times,
  {
    fajr: {
      name: "Fajr",
      label: "Fajr",
      time: "05:01",
      iso: "2026-08-30T05:01:00Z",
    },
  },
  Date.parse("2026-08-29T12:00:00Z"),
);
assert.equal(context.formatBarText(atDhuhr, absoluteSettings), "Dhuhr now");
assert.equal(context.formatBarText(atDhuhr, initialRelativeSettings), "D now");
assert.equal(context.formatBarText(afterDhuhr, absoluteSettings), "Dhuhr 7m ago");
assert.equal(context.formatBarText(afterDhuhr, initialRelativeSettings), "D 7m ago");

const noUpcomingPrayer = context.deriveState(
  times,
  null,
  Date.parse("2026-08-29T12:21:00Z"),
);
assert.equal(noUpcomingPrayer.nextLabel, "");
assert.equal(context.formatBarText(noUpcomingPrayer, absoluteSettings), "--");

assert.deepEqual(
  Array.from(
    [
      "full-time",
      "full-relative",
      "initial-time",
      "initial-relative",
    ].map((mode) => context.nextTextMode(mode)),
  ),
  ["full-relative", "initial-time", "initial-relative", "full-time"],
);

const defaults = context.sanitizeSettings({});
assert.equal(defaults.locationMode, "auto");
assert.equal(defaults.method, 4);
assert.equal(defaults.showIcon, false);
assert.equal(defaults.textMode, "initial-time");

const configured = context.sanitizeSettings({
  locationMode: "manual",
  locationName: "Riyadh",
  latitude: 24.7136,
  longitude: 46.6753,
  timezone: "Asia/Riyadh",
  method: 3,
  school: 1,
  highLatitude: 2,
  hijriAdjustment: 2,
  ramadanIsha: false,
  showIcon: true,
  textMode: "full-relative",
  offsets: { fajr: -30, asr: 4, isha: 99 },
});
assert.equal(configured.locationMode, "manual");
assert.equal(configured.method, 3);
assert.equal(configured.school, 1);
assert.equal(configured.showIcon, true);
assert.equal(configured.offsets.fajr, -15);
assert.equal(configured.offsets.asr, 4);
assert.equal(configured.offsets.isha, 15);

const merged = context.mergeSettings(configured, {
  offsets: { asr: -3 },
});
assert.equal(merged.offsets.fajr, -15);
assert.equal(merged.offsets.asr, -3);
assert.equal(merged.locationName, "Riyadh");

const invalidManualLocation = context.sanitizeSettings({
  locationMode: "manual",
  latitude: 999,
  longitude: 999,
});
assert.equal(invalidManualLocation.locationMode, "auto");

const tickMs = Date.parse("2026-11-17T12:00:00Z");
assert.equal(context.clockJumped(0, tickMs), false);
assert.equal(context.clockJumped(undefined, tickMs), false);
assert.equal(context.clockJumped(NaN, tickMs), false);
assert.equal(context.clockJumped(tickMs, tickMs + 1000), false);
assert.equal(context.clockJumped(tickMs, tickMs + 3 * 60 * 1000), true);
assert.equal(context.clockJumped(tickMs, tickMs - 60 * 60 * 1000), true);

// Vertical (left or right) bar display.
const crescent = String.fromCodePoint(0xf0979);
const lines = (state, settings) =>
  Array.from(context.verticalBarLines(state, settings));
const nextAt = (label, time, secondsToNext) => ({
  state: "ready",
  nextLabel: label,
  nextTime: time,
  secondsToNext,
  withinElapsed: false,
  currentLabel: "",
  secondsSinceAdhan: -1,
});
const elapsedAt = (label, secondsSinceAdhan) => ({
  ...nextAt("Isha", "18:35", 4000),
  withinElapsed: true,
  currentLabel: label,
  secondsSinceAdhan,
});

assert.equal(defaults.verticalTextMode, "");
assert.equal(context.defaultSettings().verticalTextMode, "");
for (const mode of ["time", "relative", "icon"]) {
  assert.equal(
    context.sanitizeSettings({ verticalTextMode: mode }).verticalTextMode,
    mode,
  );
}
for (const invalid of ["full-time", "Time", "", null, 3]) {
  assert.equal(
    context.sanitizeSettings({ verticalTextMode: invalid }).verticalTextMode,
    "",
  );
}
const verticalMerged = context.mergeSettings(configured, {
  verticalTextMode: "icon",
});
assert.equal(verticalMerged.verticalTextMode, "icon");
assert.equal(verticalMerged.textMode, "full-relative");
assert.equal(
  context.mergeSettings(verticalMerged, { showIcon: false }).verticalTextMode,
  "icon",
);
assert.equal(
  context.mergeSettings(verticalMerged, { verticalTextMode: "bogus" })
    .verticalTextMode,
  "",
);

assert.deepEqual(
  ["full-time", "full-relative", "initial-time", "initial-relative"].map(
    (textMode) => context.effectiveVerticalTextMode({ textMode }),
  ),
  ["time", "relative", "time", "relative"],
);
assert.equal(
  context.effectiveVerticalTextMode({
    textMode: "full-relative",
    verticalTextMode: "time",
  }),
  "time",
);
assert.equal(
  context.effectiveVerticalTextMode({
    textMode: "initial-time",
    verticalTextMode: "icon",
  }),
  "icon",
);
assert.equal(context.effectiveVerticalTextMode({}), "time");

assert.deepEqual(
  ["time", "relative", "icon", "", "bogus"].map((mode) =>
    context.nextVerticalTextMode(mode),
  ),
  ["relative", "icon", "time", "time", "time"],
);

const timeMode = { verticalTextMode: "time" };
const relativeMode = { verticalTextMode: "relative" };
const maghrib = nextAt("Maghrib", "17:05", 540);
assert.deepEqual(lines(maghrib, timeMode), ["M", "17", "05"]);
assert.deepEqual(lines(nextAt("Asr", "15:24", 120), timeMode), [
  "A",
  "15",
  "24",
]);
assert.deepEqual(lines(nextAt("Asr", "", 120), timeMode), ["A"]);
assert.deepEqual(lines(maghrib, relativeMode), ["M", "9m"]);
assert.deepEqual(lines(nextAt("Asr", "15:24", 8100), relativeMode), [
  "A",
  "2h",
  "15m",
]);
assert.deepEqual(lines(nextAt("Asr", "15:24", 7200), relativeMode), [
  "A",
  "2h",
]);
assert.deepEqual(lines(nextAt("Fajr", "05:00", 30), relativeMode), [
  "F",
  "<1m",
]);
assert.deepEqual(lines(nextAt("Isha", "18:35", 600), {}), ["I", "18", "35"]);
assert.deepEqual(
  lines(nextAt("Isha", "18:35", 600), { textMode: "full-relative" }),
  ["I", "10m"],
);
assert.deepEqual(lines(nextAt("Sunrise", "06:20", 600), timeMode), [
  "S",
  "06",
  "20",
]);

for (const settings of [timeMode, relativeMode]) {
  assert.deepEqual(lines(elapsedAt("Maghrib", 0), settings), ["M", "now"]);
  assert.deepEqual(lines(elapsedAt("Maghrib", 59), settings), ["M", "now"]);
  assert.deepEqual(lines(elapsedAt("Maghrib", 300), settings), [
    "M",
    "5m",
    "ago",
  ]);
}
assert.deepEqual(lines(atDhuhr, timeMode), ["D", "now"]);
assert.deepEqual(lines(afterDhuhr, relativeMode), ["D", "7m", "ago"]);

const errored = { ...maghrib, state: "error" };
assert.deepEqual(lines(errored, timeMode), ["--"]);
assert.deepEqual(lines(errored, relativeMode), ["--"]);
assert.deepEqual(lines(noUpcomingPrayer, timeMode), ["--"]);
assert.deepEqual(lines(nextAt("", "", -1), relativeMode), ["--"]);

assert.deepEqual(lines(maghrib, { verticalTextMode: "icon" }), [crescent]);
assert.deepEqual(
  lines(maghrib, { verticalTextMode: "icon", showIcon: true }),
  [crescent],
);
assert.deepEqual(lines(errored, { verticalTextMode: "icon" }), [crescent]);
assert.deepEqual(lines(maghrib, { ...timeMode, showIcon: true }), [
  crescent,
  "M",
  "17",
  "05",
]);
assert.deepEqual(lines(maghrib, { ...relativeMode, showIcon: true }), [
  crescent,
  "M",
  "9m",
]);
assert.deepEqual(lines(elapsedAt("Asr", 120), { showIcon: true }), [
  crescent,
  "A",
  "2m",
  "ago",
]);
assert.deepEqual(lines(null, timeMode), []);

assert.equal(context.statusText(maghrib), "Maghrib in 9m (17:05)");
assert.equal(context.statusText(nextAt("Asr", "", 8100)), "Asr in 2h 15m");
assert.equal(context.statusText(elapsedAt("Maghrib", 300)), "Maghrib 5m ago");
assert.equal(context.statusText(elapsedAt("Maghrib", 0)), "Maghrib now");
assert.equal(context.statusText(errored), "Prayer data unavailable");
assert.equal(context.statusText(noUpcomingPrayer), "");
assert.equal(
  context.barTooltipText(maghrib, "Riyadh", true),
  "Prayer Times · Maghrib in 9m (17:05) · Riyadh · Right-click to change format",
);
assert.equal(
  context.barTooltipText(elapsedAt("Maghrib", 300), "", true),
  "Prayer Times · Maghrib 5m ago · Right-click to change format",
);
assert.equal(
  context.barTooltipText(noUpcomingPrayer, "Riyadh", true),
  "Prayer Times · Riyadh · Right-click to change format",
);
assert.equal(
  context.barTooltipText(maghrib, "Riyadh", false),
  "Prayer Times · Riyadh · Right-click to change format",
);
assert.equal(
  context.barTooltipText(maghrib, "", false),
  "Prayer Times · Right-click to change format",
);

assert.deepEqual(
  Array.from(context.VERTICAL_TEXT_MODE_OPTIONS, (option) => option.value),
  ["time", "relative", "icon"],
);

console.log("prayer logic: ok");
