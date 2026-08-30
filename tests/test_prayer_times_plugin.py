#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import runpy
import stat
import tempfile
import unittest
from datetime import date, datetime, timezone
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND = REPO_ROOT / "prayer-times-json"


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

    def test_automatic_location_uses_ipinfo_result_and_timezone(self) -> None:
        response = json.dumps(
            {
                "ip": "178.73.84.80",
                "city": "Riyadh",
                "region": "Riyadh Region",
                "country": "SA",
                "loc": "24.6877,46.7219",
                "timezone": "Asia/Riyadh",
            }
        )
        fetch_globals = self.module["fetch_geo_location"].__globals__
        original = fetch_globals["curl_text"]
        fetch_globals["curl_text"] = lambda url: response
        try:
            with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
                cache_dir = Path(directory)
                result = self.module["fetch_geo_location"](
                    cache_dir, datetime(2026, 8, 30, tzinfo=timezone.utc)
                )
                cached = json.loads((cache_dir / "location.json").read_text())
        finally:
            fetch_globals["curl_text"] = original

        self.assertEqual(result["locationLabel"], "Riyadh")
        self.assertEqual(result["timezone"], "Asia/Riyadh")
        self.assertEqual(cached["provider"], "ipinfo")
        self.assertEqual(self.module["LOCATION_URL"], "https://ipinfo.io/json")

    def test_location_cache_from_previous_provider_is_invalidated(self) -> None:
        with tempfile.TemporaryDirectory(prefix="prayer-location-") as directory:
            cache_dir = Path(directory)
            (cache_dir / "location.json").write_text(json.dumps({
                "latitude": 18.2949297,
                "longitude": 42.7333332,
                "locationLabel": "Khamis Mushait, Saudi Arabia",
                "timezone": "Asia/Riyadh",
                "provider": "ipwho",
            }))

            result = self.module["cached_location"](
                cache_dir, datetime.now(timezone.utc)
            )

        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
