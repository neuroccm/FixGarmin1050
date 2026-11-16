import replay_gen as rg

S = 10 / 3.6


def test_speed_class():
    assert rg.speed_class(None) == 0
    assert rg.speed_class(1.9) == 0
    assert rg.speed_class(2.5) == 1
    assert rg.speed_class(S + 0.01) == 2


def test_timer_timeline_states():
    # FIT timer events at offsets: start, auto stop, auto start, manual stop
    ev = [(5, "start", "manual"), (8, "stop_all", "auto"), (10, "start", "auto"), (12, "stop_all", "manual")]
    tl = rg.timer_timeline(ev, t0=0, n=14)
    assert tl[:5] == [0] * 5            # OFF before the first start
    assert tl[5:8] == [3, 3, 3]         # ON
    assert tl[8:10] == [2, 2]           # auto stop -> PAUSED
    assert tl[10:12] == [3, 3]
    assert tl[12:] == [1, 1]            # manual stop -> STOPPED


def test_rle_and_pack_roundtrip():
    seq = [(2, 1, 0)] * 3 + [(0, 1, 0)] + [(2, 3, 1)] * 2
    segs = rg.rle(seq)
    assert segs == [(3, (2, 1, 0)), (1, (0, 1, 0)), (2, (2, 3, 1))]
    b = rg.pack(segs)
    assert len(b) == 9
    assert b[0:3] == bytes([3, 0, 2 | (1 << 2) | (0 << 4)])
    assert rg.unpack(b) == segs


def test_rle_splits_long_runs():
    segs = rg.rle([(0, 0, 0)] * 70000)
    assert [c for c, _ in segs] == [65535, 70000 - 65535]


def test_expected_alerts_matches_watchdog_rule():
    # timer STOPPED from t=0; still for 100 s, then moving fast for 200 s
    seq = [(0, 1, 0)] * 100 + [(2, 1, 0)] * 200
    first, count = rg.expected_alerts(seq, t=30, r=60)
    assert first == 130                 # 31st consecutive fast second (index 100 + 30)
    assert count == 1 + (299 - 130) // 60   # raise + repeats every 60 s


def test_stub_module_when_data_missing():
    src = rg.render_data({}, available=False)
    assert "const AVAILABLE = false;" in src
    tests = rg.render_tests({}, available=False)
    assert "(:test)" in tests and "skipped" in tests


# --- Probe logs from real rides (Nov 2026): 5 s samples plus exact timer changes ---

PROBE = """\
100 INIT pc=10
104 P t=0 v=0.000000 d=null
109 P t=0 v=2.500000 d=null
110 T 0->3
114 P t=3 v=5.000000 d=10.000000
119 P t=3 v=5.000000 d=35.000000
121 T 3->2
122 PAUSED box ts=2 shown
124 P t=2 v=0.000000 d=40.000000
129 P t=2 v=0.000000 d=40.000000
200 INIT pc=20
204 P t=1 v=null d=40.000000
206 T 1->0
209 P t=0 v=null d=null
garbage line
""".splitlines()


def test_probe_sessions_split_at_init():
    ses = rg.probe_sessions(PROBE)
    assert [len(s) for s in ses] == [10, 4]
    assert ses[1][0] == (200, "INIT pc=20")


def test_probe_sessions_split_at_log_gap():
    ses = rg.probe_sessions(["10 P t=3 v=1.0 d=1.0", "15 P t=3 v=1.0 d=2.0", "60 P t=3 v=1.0 d=3.0"])
    assert [len(s) for s in ses] == [2, 1]


def test_probe_series_one_tuple_per_second():
    seq = rg.probe_series(rg.probe_sessions(PROBE)[0])
    assert len(seq) == 129 - 100 + 1
    assert seq[0:5] == [(0, 0, 0)] * 5          # 100-104: still, timer OFF
    assert seq[5:10] == [(1, 0, 0)] * 5         # 105-109: 2.5 m/s is "moving" but not "fast"
    assert seq[10:20] == [(2, 3, 1)] * 10       # 110-119: Start pressed at 110, fast, distance advancing
    assert seq[20] == (0, 3, 1)                 # 120: still ON; the 124 sample is at rest
    assert seq[21:25] == [(0, 2, 1)] * 4        # 121-124: auto-pause from the exact T line
    assert seq[25:30] == [(0, 2, 0)] * 5        # 125-129: distance no longer advancing


def test_probe_series_starts_in_the_timer_state_before_the_first_change():
    seq = rg.probe_series(rg.probe_sessions(PROBE)[1])
    assert seq[0] == (0, 1, 0)                  # the session begins STOPPED (from "T 1->0")
    assert seq[-1] == (0, 0, 0)


def test_expected_starts_counts_rides():
    assert rg.expected_starts([(0, 0, 0)] * 5 + [(2, 3, 1)] * 5 + [(0, 1, 0)] * 2 + [(0, 0, 0)] * 3) == 1
    assert rg.expected_starts([(0, 1, 0)] * 3 + [(0, 0, 0)] * 2) == 1       # already STOPPED when the field loads
    assert rg.expected_starts([(0, 0, 0)] * 9) == 0


def test_render_tests_for_probe_rides():
    rides = {"NOV00": {"packed": b"\x05\x00\x00", "meta": {"SECONDS": 400, "STARTS": 1}}}
    src = rg.render_tests(rides, available=True)
    assert "function replayNov00Life(" in src and "Replay.lifeStarts(ReplayData.NOV00)" in src
    assert "function replayNov00NoMovingW00(" in src and "function replayNov00NoFrozenW01(" in src
    assert "OCT3" not in src                     # Oct rides absent: no Oct tests


def test_oct3_replay_asserts_exact_time_and_count_and_runs_through_the_field():
    rides = {"OCT3": {"packed": b"\x05\x00\x00", "meta": {"STOP": 129, "FIRST": 257, "COUNT": 2, "WIN_END": 330}}}
    src = rg.render_tests(rides, available=True)
    assert "r[0] == 257" in src and "r[1] == 2" in src          # not "within 2": a missing repeat must fail
    assert ".abs()" not in src
    assert "function replayOct3ThroughField(" in src and "Replay.fieldFirstAndTones(ReplayData.OCT3, 330)" in src


def test_probe_series_skips_truncated_lines():
    seq = rg.probe_series([(100, "P t=3 v=5.000000 d=10.000000"), (105, "P t=3 v=5.0000"), (106, "P t=3 v=5.0 d=nul"), (110, "P t=3 v=5.000000 d=60.000000")])
    assert len(seq) == 11 and seq[-1] == (2, 3, 1)
