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

console.log("prayer logic: ok");
