"""Run with Blender's bundled NumPy: blender -b --python this_file.py."""
from pathlib import Path
import sys
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from motion_metrics import overlap_metrics, pops, spacing_crest, spikes, strike_craft, strike_metrics
except (ModuleNotFoundError, ImportError):
    overlap_metrics = pops = spacing_crest = spikes = strike_craft = strike_metrics = None


def chop(hold_at_top=1):
    """A weapon point at 24 fps: still, a wind-up moving back 5 cm a frame on frames 2-8, a hold, then a
    strike gaining 10, 20 and 30 cm a frame to the hit on frame 9 + hold + 3, then still again."""
    u = np.array([0.0, -0.6, -0.8])                    # forward and down
    steps = [0.0, 0.0] + [-0.05] * 6 + [0.0] * hold_at_top + [0.1, 0.2, 0.3] + [0.0] * 6
    along = np.concatenate([[0.0], np.cumsum(steps)])
    return np.array([0.0, 0.0, 1.5]) + along[:, None] * u


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


class StrikeTests(unittest.TestCase):
    def test_known_chop(self):
        self.assertIsNotNone(strike_metrics, "strike metric is not implemented")
        # wind-up frames 2-8 back, hold 8-9, strike 9-12 (10, 20, 30 cm), hit on frame 12
        r = strike_metrics(chop(), 24, impact=12, start=8, end=15)
        self.assertAlmostEqual(r["tip_speed_m_s"], 0.25 * 24)     # central difference on frame 11
        self.assertEqual(r["peak_frame"], 11)
        self.assertEqual(r["impact_offset_frames"], 1)
        self.assertEqual(r["strike_start_frame"], 10)              # frame 9 moves at 1.2 m/s, under a quarter of 6
        self.assertAlmostEqual(r["strike_s"], 1 / 24)
        self.assertAlmostEqual(r["wind_up_s"], 6 / 24)             # the hold at the top is not wind-up
        self.assertAlmostEqual(r["top_travel_m"], 0.5 * 0.6)       # frames 10 to 12 travel 0.5 m, 0.6 of it level

    def test_a_longer_hold_does_not_change_the_wind_up(self):
        r = strike_metrics(chop(hold_at_top=4), 24, impact=15, start=11, end=18)
        self.assertAlmostEqual(r["wind_up_s"], 6 / 24)

    def test_no_wind_up(self):
        P = chop()
        P[:9] = P[8]                                     # starts from the top: nothing moves back
        self.assertAlmostEqual(strike_metrics(P, 24, impact=12, start=8, end=15)["wind_up_s"], 0.0)


class PopTests(unittest.TestCase):
    def track(self):
        S = np.zeros((10, 1, 3))
        S[5, 0, 0] = 0.01                                # one point jumps 1 cm on frame 5
        return S

    def test_a_jump_is_found(self):
        self.assertIsNotNone(pops, "pop metric is not implemented")
        value, frame, point = pops(self.track(), loop=False)
        self.assertAlmostEqual(value, 0.02)
        self.assertEqual((frame, point), (5, 0))

    def test_an_exempt_hit_is_left_out(self):
        value, frame, _ = pops(self.track(), exempt={5}, loop=False)
        self.assertAlmostEqual(value, 0.01)
        self.assertEqual(frame, 4)
        self.assertAlmostEqual(pops(self.track(), exempt={4, 5, 6}, loop=False)[0], 0.0)

    def test_a_loop_wraps_round(self):
        S = np.zeros((10, 1, 3))
        S[0, 0, 0] = 0.01
        self.assertAlmostEqual(pops(S, loop=True)[0], 0.02)
        self.assertAlmostEqual(pops(S, loop=False)[0], 0.01)   # frame 0 has no frame before it


class SpikeTests(unittest.TestCase):
    def swing(self, frames, size=0.5):
        """One point swinging round a circle and back, eased: a smooth motion of `frames` frames."""
        t = np.linspace(0, 1, frames)
        a = np.pi * (1 - np.cos(np.pi * t))           # eased angle, 0 to 2 pi
        return np.stack([size * np.cos(a), size * np.sin(a), np.zeros(frames)], 1)[:, None, :]

    def test_speed_does_not_change_it(self):
        self.assertIsNotNone(spikes, "spike measure is not implemented")
        slow = spikes(self.swing(90), loop=False)[0]
        fast = spikes(self.swing(30), loop=False)[0]   # the same swing three times faster
        self.assertLess(slow, 1.5)
        self.assertLess(fast, 1.5)
        self.assertLess(abs(slow - fast), 0.3)

    def sway(self):
        """A slow sway of 1 cm, as an idle breathes."""
        S = np.zeros((60, 1, 3))
        S[:, 0, 0] = 0.01 * np.sin(np.arange(60) * 2 * np.pi / 60)
        return S

    def test_one_frame_off_its_path_is_found(self):
        S = self.sway()
        S[30, 0, 2] += 0.01                              # 1 cm off the path on frame 30
        value, frame, _ = spikes(S, loop=True)
        self.assertGreater(value, 5)
        self.assertEqual(frame, 30)

    def test_it_is_relative_to_the_motion(self):
        S = self.swing(60)                               # the same 1 cm in a swing moving 8 cm a frame
        S[30, 0, 2] += 0.01
        self.assertLess(spikes(S, loop=False)[0], 3)

    def test_an_exempt_hit_is_left_out(self):
        S = self.sway()
        S[30, 0, 2] += 0.01
        self.assertLess(spikes(S, exempt=set(range(28, 33)), loop=True)[0], 1.5)

    def test_stillness_is_not_a_spike(self):
        S = np.zeros((40, 1, 3))
        S[:, 0, 0] = 1e-5 * np.sin(np.arange(40))      # sensor-sized wobble, far under the floor
        self.assertLess(spikes(S, loop=True)[0], 0.1)


class SpacingTests(unittest.TestCase):
    def test_a_sinusoid_scores_one_at_any_period(self):
        self.assertIsNotNone(spacing_crest, "crest spacing is not implemented")
        for period in (8, 16, 64):
            t = np.arange(period * 3) * 2 * np.pi / period
            P = np.stack([0.05 * np.sin(t), np.zeros_like(t), 0.02 * np.sin(t)], 1)   # back and forth on a line
            # 1 exactly in continuous time; sampling at 8 frames a period misses the speed's peak by up to 8%
            self.assertAlmostEqual(spacing_crest(P, loop=True), 1.0, delta=0.1)

    def test_linear_keys_score_high(self):
        k = np.concatenate([np.linspace(0, 0.05, 12, endpoint=False), np.linspace(0.05, 0, 12, endpoint=False)])
        P = np.stack([k, np.zeros_like(k), np.zeros_like(k)], 1)      # a triangle wave: velocity flips in a kink
        self.assertGreater(spacing_crest(P, loop=True), 2.5)

    def test_stillness_has_no_score(self):
        self.assertIsNone(spacing_crest(np.zeros((30, 3)), loop=True))


def ease(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def swing(n=24, follow=True, offsets=(0, 1, 2, 2), roll=False, drop=0.06):
    """A strike about a shoulder at the origin in the ground plane, 24 fps: from -40 degrees the point speeds up
    (ease in) to 90 degrees at frame 12, its fastest, then (follow) carries on 60 degrees while slowing, or stops
    dead as a strike keyed to end on the hit does. Links turn about Z with an eased profile, each `offsets`
    frames later than the one it hangs from."""
    t = np.arange(n, dtype=float)
    u = np.clip((t - 4) / 8, 0, 1)
    after = np.clip((t - 12) / 6, 0, 1)
    a = -40 + 130 * u * u + (np.where(t > 12, 60 * np.sin(after * np.pi / 2), 0) if follow else 0)
    r = np.radians(a)
    tip = np.stack([0.9 * np.cos(r), 0.9 * np.sin(r), np.zeros(n)], 1)
    tangent = np.stack([-np.sin(r), np.cos(r), np.zeros(n)], 1)
    up = np.tile([0.0, 0.0, 1.0], (n, 1))
    edge, normal = (up, -tangent) if roll else (tangent, up)

    def quats(shift):
        ang = np.radians(30 * ease((t - 4 - shift) / 12))
        return np.stack([np.cos(ang / 2), np.zeros(n), np.zeros(n), np.sin(ang / 2)], 1)
    links = dict(zip(("hips", "chest", "arm", "hand"), (quats(o) for o in offsets)))
    hz = 0.8 - drop * ease((t - 4) / 8)
    return tip, normal, edge, np.zeros((n, 3)), hz, 0.6, links


@unittest.skipIf(strike_craft is None, "NumPy is not available")
class StrikeCraftTests(unittest.TestCase):
    def craft(self, kind="h", **kw):
        tip, nm, ed, sh, hz, leg, links = swing(**kw)
        return strike_craft(tip, nm, ed, sh, hz, leg, links, 24, kind=kind, start=4, end=15)

    def test_a_hips_first_chain_lags_by_its_offsets(self):
        r = self.craft(offsets=(0, 1, 2, 2))            # chest 1 frame after the hips, the arm 1 after the chest
        self.assertAlmostEqual(r["chain_lag_chest_hips"], 1.0, delta=0.2)
        self.assertAlmostEqual(r["chain_lag_arm_chest"], 1.0, delta=0.2)
        self.assertGreater(r["chain_lag_min"], 0.75)

    def test_a_body_moving_as_one_does_not_lag(self):
        r = self.craft(offsets=(0, 0, 0, 0))
        self.assertLess(abs(r["chain_lag_min"]), 0.2)

    def test_a_vertical_strike_only_needs_the_arm_after_the_chest(self):
        r = self.craft(kind="v", offsets=(0, 0, 1, 1))  # the hips do not lead a chop down
        self.assertAlmostEqual(r["chain_lag_min"], r["chain_lag_arm_chest"])
        self.assertGreater(r["chain_lag_min"], 0.75)

    def test_an_edge_on_the_cut_and_one_rolled_off_it(self):
        good, rolled = self.craft(), self.craft(roll=True)
        self.assertLess(good["edge_off_plane_deg"], 2)
        self.assertLess(good["edge_to_cut_deg"], 2)
        self.assertGreater(rolled["edge_off_plane_deg"], 80)

    def test_follow_through_against_a_dead_stop(self):
        self.assertGreater(self.craft(follow=True)["follow_deg"], 40)
        self.assertLess(self.craft(follow=False)["follow_deg"], 5)

    def test_frames_before_the_hit_key_are_not_follow_through(self):
        tip, nm, ed, sh, hz, leg, links = swing(follow=False)
        r = strike_craft(tip, nm, ed, sh, hz, leg, links, 24, start=4, end=15, impact=12)
        self.assertLess(r["follow_deg"], 5)
        late = strike_craft(tip, nm, ed, sh, hz, leg, links, 24, start=4, end=15, impact=9)   # a peak after the key
        self.assertLess(late["follow_deg"], 5)

    def test_hips_drop_against_the_need_of_the_kind(self):
        r = self.craft(drop=0.06)                       # 10% of a 0.6 m leg
        self.assertAlmostEqual(r["hips_drop_leg"], 0.1, places=3)
        self.assertAlmostEqual(r["hips_drop_margin"], 0.02, places=3)
        self.assertLess(self.craft(kind="v", drop=0.06)["hips_drop_margin"], 0)


if __name__ == "__main__":
    result = unittest.main(argv=[sys.argv[0]], exit=False).result
    if not result.wasSuccessful():
        raise SystemExit(1)
