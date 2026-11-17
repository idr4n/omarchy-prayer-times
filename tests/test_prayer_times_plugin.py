#!/usr/bin/env python3
from __future__ import annotations

import argparse
import io
import json
import os
import runpy
import stat
import tempfile
import unittest
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND = REPO_ROOT / "prayer-times-json"
LOCATION_NOW = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)


def aladhan_payload(*, hijri_month: int = 9) -> dict[str, object]:
    return {
        "data": {
            "timings": {
                "Fajr": "05:00",
                "Sunrise": "06:20",
                "Dhuhr": "12:00",
                "Asr": "15:00",
                "Maghrib": "18:00",
                "Isha": "19:30",
            },
            "date": {
                "hijri": {
                    "day": "10",
                    "month": {"number": hijri_month},
                    "year": "1448",
                    "designation": {"abbreviated": "AH"},
                }
            },
            "meta": {"timezone": "Asia/Riyadh"},
        }
    }


class PrayerTimesBackendTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = runpy.run_path(str(BACKEND))

    def args(self, *extra: str) -> argparse.Namespace:
        return self.module["parse_args"](
            [
                "--method",
                "4",
                "--school",
                "0",
                "--offsets",
                "{}",
                *extra,
            ]
        )

    def test_offsets_are_complete_and_bounded(self) -> None:
        offsets = self.module["parse_offsets"](
            json.dumps({"fajr": -99, "asr": 4, "isha": 99})
        )

        self.assertEqual(offsets["fajr"], -15)
        self.assertEqual(offsets["asr"], 4)
        self.assertEqual(offsets["isha"], 15)
        self.assertEqual(offsets["maghrib"], 0)

    def test_calculation_variant_changes_with_user_settings(self) -> None:
        baseline = self.args()
        hanafi = self.args("--school", "1")
        adjusted = self.args("--offsets", '{"asr":3}')

        self.assertNotEqual(
            self.module["config_key"](baseline),
            self.module["config_key"](hanafi),
        )
        self.assertNotEqual(
            self.module["config_key"](baseline),
            self.module["config_key"](adjusted),
        )

    def test_ramadan_and_manual_offsets_are_applied_deterministically(self) -> None:
        enabled = self.args(
            "--ramadan-isha",
            "1",
            "--offsets",
            '{"asr":4,"isha":-2}',
        )
        disabled = self.args(
            "--ramadan-isha",
            "0",
            "--offsets",
            '{"asr":4,"isha":-2}',
        )

        enabled_result = self.module["normalize_aladhan"](
            aladhan_payload(), date(2026, 2, 27), 24.7136, 46.6753, enabled, "a"
        )
        disabled_result = self.module["normalize_aladhan"](
            aladhan_payload(), date(2026, 2, 27), 24.7136, 46.6753, disabled, "b"
        )

        self.assertEqual(enabled_result["timings"]["Asr"], "15:04")
        self.assertEqual(enabled_result["timings"]["Isha"], "19:58")
        self.assertEqual(disabled_result["timings"]["Isha"], "19:28")

    def test_post_midnight_isha_rolls_forward_and_extends_payload_expiry(
        self,
    ) -> None:
        day = date(2026, 6, 21)
        zone = ZoneInfo("Europe/Helsinki")
        day_payload = {
            "date": day.isoformat(),
            "timings": {
                "Fajr": "01:22",
                "Sunrise": "03:54",
                "Dhuhr": "13:22",
                "Asr": "18:04",
                "Maghrib": "22:50",
                "Isha": "01:22",
            },
        }

        times = self.module["build_times"](day_payload, zone)

        self.assertEqual(times[-1]["time"], "01:22")
        self.assertEqual(times[-1]["iso"], "2026-06-22T01:22:00+03:00")
        self.assertEqual(
            self.module["payload_expiry"](day, zone, times),
            "2026-06-22T01:42:00+03:00",
        )

    def test_api_query_carries_school_high_latitude_and_hijri_adjustment(self) -> None:
        args = self.args(
            "--school",
            "1",
            "--high-latitude",
            "2",
            "--hijri-adjustment",
            "-1",
        )
        requested: list[str] = []

        def fake_curl(url: str) -> str:
            requested.append(url)
            return json.dumps(aladhan_payload(hijri_month=3))

        args_globals = self.module["fetch_day"].__globals__
        original = args_globals["curl_text"]
        args_globals["curl_text"] = fake_curl
        try:
            result = self.module["fetch_day"](
                date(2026, 8, 30),
                24.7136,
                46.6753,
                args,
                "Asia/Riyadh",
                "variant",
            )
        finally:
            args_globals["curl_text"] = original

        self.assertEqual(result["timezone"], "Asia/Riyadh")
        self.assertEqual(len(requested), 1)
        self.assertIn("school=1", requested[0])
        self.assertIn("latitudeAdjustmentMethod=2", requested[0])
        self.assertIn("adjustment=-1", requested[0])
        self.assertIn("timezonestring=Asia%2FRiyadh", requested[0])

    def test_settings_round_trip_is_private_and_rejects_symlink_targets(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-settings-") as directory:
            state_home = Path(directory) / "state"
            with patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}):
                payload = {"method": 3, "showIcon": True}
                self.module["write_settings"](json.dumps(payload))
                target = self.module["default_settings_path"]()

                self.assertEqual(json.loads(self.module["read_settings"]()), payload)
                self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)

                target.unlink()
                sentinel = Path(directory) / "sentinel.json"
                sentinel.write_text('{"safe":true}\n')
                target.symlink_to(sentinel)
                with self.assertRaisesRegex(ValueError, "regular file"):
                    self.module["write_settings"]('{"method":4}')
                self.assertEqual(sentinel.read_text(), '{"safe":true}\n')

    def test_settings_read_creates_parent_for_file_watcher(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-settings-") as directory:
            target = (
                Path(directory)
                / "missing"
                / "omarchy"
                / "settings"
                / "prayer-times.json"
            )

            result = self.module["read_settings"](target)

            self.assertEqual(result, "{}")
            self.assertTrue(target.parent.is_dir())
            self.assertEqual(stat.S_IMODE(target.parent.stat().st_mode), 0o700)

    def test_settings_patch_preserves_other_instance_values(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-settings-") as directory:
            target = Path(directory) / "prayer-times.json"
            original = {
                "locationMode": "manual",
                "locationName": "Helsinki, Finland",
                "latitude": 60.1699,
                "longitude": 24.9384,
                "timezone": "Europe/Helsinki",
                "offsets": {"fajr": 2, "asr": 4},
            }
            self.module["write_settings"](json.dumps(original), target)

            self.module["patch_settings"](
                json.dumps({
                    "textMode": "full-relative",
                    "offsets": {"asr": 5},
                }),
                target,
            )
            result = json.loads(self.module["read_settings"](target))

        self.assertEqual(result["locationName"], "Helsinki, Finland")
        self.assertEqual(result["textMode"], "full-relative")
        self.assertEqual(result["offsets"], {"fajr": 2, "asr": 5})

    def test_settings_patch_command_reports_write_failures(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-settings-") as directory:
            state_home = Path(directory) / "state"
            target = (
                state_home / "omarchy" / "settings" / "prayer-times.json"
            )
            target.parent.mkdir(parents=True)
            sentinel = Path(directory) / "sentinel.json"
            sentinel.write_text('{"safe":true}\n')
            target.symlink_to(sentinel)

            with (
                patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}),
                patch("sys.stderr", new_callable=io.StringIO) as error,
            ):
                exit_code = self.module["main"](
                    ["--patch-settings", '{"textMode":"full-relative"}']
                )
            error_text = error.getvalue()
            sentinel_text = sentinel.read_text()

        self.assertEqual(exit_code, 1)
        self.assertIn("regular file", error_text)
        self.assertEqual(sentinel_text, '{"safe":true}\n')

    def test_automatic_location_uses_ipwho_over_ipv4(self) -> None:
        response = json.dumps(
            {
                "success": True,
                "city": "Riyadh",
                "country": "Saudi Arabia",
                "latitude": 24.6877293,
                "longitude": 46.7218526,
                "timezone": {"id": "Asia/Riyadh"},
            }
        )
        requests = []
        fetch_globals = self.module["fetch_geo_location"].__globals__
        original = fetch_globals["curl_text"]

        def fake_curl(url: str, *, ipv4: bool = False) -> str:
            requests.append((url, ipv4))
            return response

        fetch_globals["curl_text"] = fake_curl
        try:
            with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
                cache_dir = Path(directory)
                result = self.module["fetch_geo_location"](
                    cache_dir, datetime(2026, 8, 30, tzinfo=timezone.utc)
                )
                cached = json.loads((cache_dir / "location.json").read_text())
        finally:
            fetch_globals["curl_text"] = original

        self.assertEqual(result["locationLabel"], "Riyadh, Saudi Arabia")
        self.assertEqual(result["timezone"], "Asia/Riyadh")
        self.assertEqual(cached["provider"], "ipwho-v4")
        self.assertEqual(requests, [(self.module["LOCATION_URL"], True)])

    def test_location_cache_from_previous_provider_is_invalidated(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            (cache_dir / "location.json").write_text(json.dumps({
                "latitude": 18.2949297,
                "longitude": 42.7333332,
                "locationLabel": "Khamis Mushait, Saudi Arabia",
                "timezone": "Asia/Riyadh",
                "provider": "ipinfo",
            }))

            result = self.module["cached_location"](
                cache_dir, datetime.now(timezone.utc)
            )

        self.assertIsNone(result)

    def write_location_cache(
        self, cache_dir: Path, label: str, age: timedelta
    ) -> Path:
        path = cache_dir / "location.json"
        path.write_text(json.dumps({
            "provider": self.module["LOCATION_PROVIDER"],
            "latitude": 24.6877293,
            "longitude": 46.7218526,
            "locationLabel": label,
            "timezone": "Asia/Riyadh",
        }))
        stamp = (LOCATION_NOW - age).timestamp()
        os.utime(path, (stamp, stamp))
        return path

    def resolve_with_fake_curl(
        self, cache_dir: Path, *extra: str, fail: bool = False
    ) -> tuple[dict[str, object] | None, list[str]]:
        requests: list[str] = []
        response = json.dumps({
            "success": True,
            "city": "Istanbul",
            "country": "Turkey",
            "latitude": 41.0082,
            "longitude": 28.9784,
            "timezone": {"id": "Europe/Istanbul"},
        })

        def fake_curl(url: str, *, ipv4: bool = False) -> str:
            requests.append(url)
            if fail:
                raise RuntimeError("network unreachable")
            return response

        fetch_globals = self.module["fetch_geo_location"].__globals__
        original = fetch_globals["curl_text"]
        fetch_globals["curl_text"] = fake_curl
        try:
            result = self.module["resolve_location"](
                self.args("--cache-dir", str(cache_dir), *extra),
                cache_dir,
                LOCATION_NOW,
            )
        finally:
            fetch_globals["curl_text"] = original
        return result, requests

    def test_recent_location_cache_is_reused_without_network(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            self.write_location_cache(cache_dir, "Riyadh, Saudi Arabia", timedelta(minutes=5))

            result, requests = self.resolve_with_fake_curl(cache_dir)

        self.assertEqual(result["locationLabel"], "Riyadh, Saudi Arabia")
        self.assertEqual(requests, [])

    def test_location_cache_older_than_reuse_window_is_redetected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            self.write_location_cache(cache_dir, "Riyadh, Saudi Arabia", timedelta(minutes=16))

            result, requests = self.resolve_with_fake_curl(cache_dir)
            cached = json.loads((cache_dir / "location.json").read_text())

        self.assertEqual(result["locationLabel"], "Istanbul, Turkey")
        self.assertEqual(cached["locationLabel"], "Istanbul, Turkey")
        self.assertEqual(requests, [self.module["LOCATION_URL"]])

    def test_refresh_location_bypasses_recent_cache(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            self.write_location_cache(cache_dir, "Riyadh, Saudi Arabia", timedelta(minutes=1))

            result, requests = self.resolve_with_fake_curl(cache_dir, "--refresh-location")

        self.assertEqual(result["locationLabel"], "Istanbul, Turkey")
        self.assertEqual(len(requests), 1)

    def test_failed_lookup_falls_back_to_old_cache_without_touching_it(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            path = self.write_location_cache(cache_dir, "Riyadh, Saudi Arabia", timedelta(days=40))
            before = path.stat().st_mtime

            result, requests = self.resolve_with_fake_curl(
                cache_dir, "--refresh-location", fail=True
            )
            after = path.stat().st_mtime

        self.assertEqual(result["locationLabel"], "Riyadh, Saudi Arabia")
        self.assertEqual(len(requests), 1)
        self.assertEqual(before, after)

    def test_no_network_uses_old_cache_without_lookup(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            self.write_location_cache(cache_dir, "Riyadh, Saudi Arabia", timedelta(days=40))

            result, requests = self.resolve_with_fake_curl(cache_dir, "--no-network")

        self.assertEqual(result["locationLabel"], "Riyadh, Saudi Arabia")
        self.assertEqual(requests, [])

    def test_future_dated_location_cache_is_not_fresh(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            self.write_location_cache(cache_dir, "Riyadh, Saudi Arabia", timedelta(days=-1))

            self.assertIsNone(
                self.module["cached_location"](
                    cache_dir, LOCATION_NOW, self.module["LOCATION_REUSE_WINDOW"]
                )
            )
            result, requests = self.resolve_with_fake_curl(cache_dir)

        self.assertEqual(result["locationLabel"], "Istanbul, Turkey")
        self.assertEqual(len(requests), 1)


if __name__ == "__main__":
    unittest.main()
