"""Run with Blender's bundled NumPy: blender -b --python this_file.py."""
from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from motion_metrics import overlap_metrics
except ModuleNotFoundError:
    overlap_metrics = None


class OverlapTests(unittest.TestCase):
    def metric(self, x, y, **kwargs):
        self.assertIsNotNone(overlap_metrics, "signed overlap metric is not implemented")
        return overlap_metrics(x, y, **kwargs)

    def test_delayed_rotation_is_measured_in_frames(self):
        x = np.sin(np.arange(80) * 2 * np.pi / 80)[:, None] * np.array([[0.04, 0.01, 0.02]])
        r = self.metric(x, np.roll(x, 5, axis=0) * 1.7)
        self.assertEqual(r["overlap_lag_frames"], 5)
        self.assertAlmostEqual(r["overlap_correlation"], 1.0)
        self.assertAlmostEqual(r["follower_ratio"], 1.7)

    def test_leading_motion_cannot_masquerade_as_positive_delay(self):
        x = np.sin(np.arange(80) * 2 * np.pi / 80)[:, None]
        self.assertEqual(self.metric(x, np.roll(x, -5, axis=0))["overlap_lag_frames"], -5)

    def test_rigid_attachment_has_zero_delay(self):
        x = np.cos(np.arange(80) * 2 * np.pi / 80)[:, None]
        self.assertEqual(self.metric(x, x * 2 + 3)["overlap_lag_frames"], 0)

    def test_stationary_driver_does_not_get_a_score(self):
        x = np.zeros((80, 3))
        self.assertIsNone(self.metric(x, x)["overlap_lag_frames"])

    def test_unrelated_motion_does_not_get_a_score(self):
        t = np.arange(80) * 2 * np.pi / 80
        self.assertIsNone(self.metric(np.sin(t)[:, None], np.sin(3 * t)[:, None])["overlap_lag_frames"])

    def test_one_shot_uses_real_overlapping_samples(self):
        x = np.exp(-((np.arange(80) - 30) / 8) ** 2)[:, None]
        y = np.vstack([np.zeros((5, 1)), x[:-5]])
        self.assertEqual(self.metric(x, y, loop=False)["overlap_lag_frames"], 5)


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0]], exit=False).result
    if not result.wasSuccessful():
        raise SystemExit(1)
