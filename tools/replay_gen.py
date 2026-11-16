#!/usr/bin/env python3
"""Generate RideGuard replay tests from real rides (outside git).

Sources, each optional:
  - the 2 and 3 Oct 2026 rides (garmin-backup-2026-10-03/, recovered/): the broken ride must raise
    R3.1, the normal one must stay silent;
  - the probe logs of eight rides in Nov 2026 (phase0-evidence/probe/): no false alerts, and exactly
    one ride opened per ride.

Writes RideGuard/test/generated/ReplayData.mc and ReplayTestsGen.mc. If no source is present,
writes stubs whose single test logs "skipped" and passes. Output is git-ignored: it is derived
from personal ride data and must never be committed.
"""
import csv
import os
import re
import sys
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ACT = os.path.join(ROOT, "garmin-backup-2026-10-03", "Garmin", "Activities")
OCT3_FIT = os.path.join(ACT, "2026-10-03-10-27-18.fit")
OCT2_FIT = os.path.join(ACT, "2026-10-02-11-17-59.fit")
OCT3_CSV = os.path.join(ROOT, "recovered", "ride_distance_per_second.csv")
PROBE_LOGS = [os.path.join(ROOT, "phase0-evidence", "probe", n) for n in ("RGSPIKE.BAK", "RGSPIKE.TXT")]
OUT_DIR = os.path.join(ROOT, "RideGuard", "test", "generated")
S = 10 / 3.6
FIT_EPOCH_OFFSET = 631065600          # unix seconds at the FIT epoch (1989-12-31T00:00:00Z)
WINDOW, OVERLAP = 300, 120            # replay windows keep each test call under the execution limit


def speed_class(v):
    if v is None or v <= 2.0:
        return 0
    return 2 if v > S else 1


def timer_timeline(events, t0, n):
    """events: (fit_ts, event_type, trigger). Returns the Connect IQ timer state for each second t0..t0+n-1."""
    state, out, ev = 0, [], sorted(events)
    j = 0
    for i in range(n):
        while j < len(ev) and ev[j][0] <= t0 + i:
            _, etype, trig = ev[j]
            if etype == "start":
                state = 3
            elif etype in ("stop_all", "stop", "stop_disable_all"):
                state = 2 if trig == "auto" else 1
            j += 1
        out.append(state)
    return out


def rle(seq):
    segs = []
    for v in seq:
        if segs and segs[-1][1] == v and segs[-1][0] < 65535:
            segs[-1] = (segs[-1][0] + 1, v)
        else:
            segs.append((1, v))
    return segs


def pack(segs):
    out = bytearray()
    for count, (cls, timer, adv) in segs:
        out += bytes([count & 0xFF, count >> 8, cls | (timer << 2) | (adv << 4)])
    return bytes(out)


def unpack(b):
    return [(b[i] | (b[i + 1] << 8), (b[i + 2] & 3, (b[i + 2] >> 2) & 3, (b[i + 2] >> 4) & 1)) for i in range(0, len(b), 3)]


def expected_alerts(seq, t=30, r=60):
    """R3.1 exactly as Watchdog implements it: run of (fast and timer != ON) > t; repeat every r."""
    run, active, last, first, count = 0, False, 0, None, 0
    for i, (cls, timer, _) in enumerate(seq):
        run = run + 1 if (cls == 2 and timer != 3) else 0
        cond = run > t
        if cond and not active:
            active, last, count = True, i, count + 1
            first = i if first is None else first
        elif cond and i - last >= r:
            last, count = i, count + 1
        elif not cond and active:
            active = False
    return first, count


def _decode(path):
    from garmin_fit_sdk import Decoder, Stream
    msgs, _ = Decoder(Stream.from_file(path)).read(convert_datetimes_to_dates=False, merge_heart_rates=False)
    ev = [(m["timestamp"], m.get("event_type"), m.get("timer_trigger"))
          for m in msgs.get("event_mesgs", []) if m.get("event") == "timer"]
    return msgs, ev


def series_oct2():
    msgs, ev = _decode(OCT2_FIT)
    rec = {m["timestamp"]: m for m in msgs.get("record_mesgs", [])}
    t0, t1 = min(e[0] for e in ev), max(e[0] for e in ev)
    tl = timer_timeline(ev, t0, t1 - t0 + 1)
    seq, last_d = [], None
    for i in range(t1 - t0 + 1):
        m = rec.get(t0 + i)
        v = m.get("enhanced_speed") if m else None
        d = m.get("distance") if m else None
        adv = 1 if (d is not None and last_d is not None and d > last_d) else 0
        if d is not None:
            last_d = d
        seq.append((speed_class(v), tl[i], adv))
    return seq, None


def series_oct3():
    _, ev = _decode(OCT3_FIT)
    rows = list(csv.DictReader(open(OCT3_CSV)))
    pts = [(int(datetime.fromisoformat(r["time_utc"]).timestamp()) - FIT_EPOCH_OFFSET, float(r["distance_m"])) for r in rows]
    t0, t1 = pts[0][0], pts[-1][0]
    dist = {}
    for (ta, da), (tb, db) in zip(pts, pts[1:]):      # spread each gap's distance evenly over its seconds
        for k in range(tb - ta):
            dist[ta + k + 1] = da + (db - da) * (k + 1) / (tb - ta)
    dist[t0] = pts[0][1]
    tl = timer_timeline(ev, t0, t1 - t0 + 1)
    seq = []
    for i in range(t1 - t0 + 1):
        v = dist[t0 + i] - dist[t0 + i - 1] if i else 0.0
        seq.append((speed_class(v), tl[i], 1 if v > 0.05 else 0))
    stop = max(e[0] for e in ev if e[1] == "stop_all") - t0
    return seq, stop


def probe_sessions(lines, gap=20):
    """Split probe log lines ("<unix> <text>") into field sessions: a new session starts at every
    INIT line and after more than `gap` seconds without a line. Unparseable lines are dropped."""
    sessions, cur, prev = [], [], None
    for line in lines:
        m = re.match(r"(\d{9,10}|\d+) (.*)", line.strip())
        if not m:
            continue
        ts, text = int(m[1]), m[2]
        if cur and (text.startswith("INIT") or ts - prev > gap):
            sessions.append(cur)
            cur = []
        cur.append((ts, text))
        prev = ts
    if cur:
        sessions.append(cur)
    return sessions


def probe_series(session):
    """One (speed_class, timer, dist_adv) per second of a probe session.

    "P t=<timer> v=<m/s|null> d=<m|null>" lines are 5 s samples: each is held back over the seconds
    since the previous sample. "T a->b" lines give the exact second of every timer change."""
    samples, changes = [], []
    for ts, text in session:
        # A line cut short by the Edge's log rotation is skipped, not parsed.
        p = re.fullmatch(r"P t=(-?\d+) v=(null|-?\d+(?:\.\d+)?) d=(null|-?\d+(?:\.\d+)?)", text)
        t = re.match(r"T (-?\d+)->(-?\d+)", text)
        if p:
            samples.append((ts, int(p[1]), None if p[2] == "null" else float(p[2]), None if p[3] == "null" else float(p[3])))
        elif t:
            changes.append((ts, int(t[1]), int(t[2])))
    if not samples:
        return []
    timer = changes[0][1] if changes else samples[0][1]
    held, prev_d = [], None
    for n, (ts, _, v, d) in enumerate(samples):
        # Did the distance advance since the previous sample? Unknown for the first sample of a
        # session; a distance that appears after "null" (timer was OFF) is compared with zero.
        held.append((ts, speed_class(v), 1 if (n > 0 and d is not None and d > (prev_d or 0.0)) else 0))
        prev_d = d
    seq, si, ci = [], 0, 0
    for now in range(session[0][0], session[-1][0] + 1):
        while ci < len(changes) and changes[ci][0] <= now:
            timer = changes[ci][2]
            ci += 1
        while si < len(held) - 1 and held[si][0] < now:
            si += 1
        seq.append((held[si][1], max(0, min(3, timer)), held[si][2]))
    return seq


def expected_starts(seq):
    """Rides in a session: one if the timer is already running or stopped when the field loads,
    plus one for every later change from OFF to anything else."""
    if not seq:
        return 0
    return (1 if seq[0][1] != 0 else 0) + sum(1 for a, b in zip(seq, seq[1:]) if a[1] == 0 and b[1] != 0)


def render_data(rides, available):
    lines = ["// GENERATED by tools/replay_gen.py from personal ride data. Do not edit. Do not commit.",
             "import Toybox.Lang;", "", "module ReplayData {", f"    const AVAILABLE = {'true' if available else 'false'};"]
    for name, r in rides.items():
        lines.append(f"    const {name} = [{', '.join(str(x) for x in r['packed'])}]b;")
        for k, v in r["meta"].items():
            lines.append(f"    const {name}_{k} = {v};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def _silent_windows(name, label, seconds):
    """Tests that a ride raises neither R3.1 nor R3.2, in overlapping windows."""
    out, start, k = [], 0, 0
    while start < seconds:
        end = min(start + WINDOW, seconds)
        for rule, tag in (("Rg.R_MOVING", "Moving"), ("Rg.R_FROZEN", "Frozen")):
            out += ["(:test)", f"function replay{label}No{tag}W{k:02d}(logger as Test.Logger) as Boolean {{",
                    f"    var r = Replay.firstAndCount(ReplayData.{name}, {rule}, {start}, {end});",
                    f"    return TestUtil.check(logger, r[1] == 0, \"normal ride raised {tag} in {start}-{end} s at \" + r[0]);", "}", ""]
        start, k = end - OVERLAP if end < seconds else end, k + 1
    return out


def render_tests(rides, available):
    head = ["// GENERATED by tools/replay_gen.py. Do not edit. Do not commit.",
            "import Toybox.Lang;", "import Toybox.Test;", ""]
    if not available:
        return "\n".join(head + ["(:test)", "function replaySkipped(logger as Test.Logger) as Boolean {",
                                 '    logger.warning("replay skipped: ride backups not found");', "    return true;", "}"]) + "\n"
    out = list(head)
    if "OCT3" in rides:
        o3 = rides["OCT3"]["meta"]
        out += ["(:test)", "function replayOct3FirstR31(logger as Test.Logger) as Boolean {",
                f"    var r = Replay.firstAndCount(ReplayData.OCT3, Rg.R_MOVING, 0, {o3['WIN_END']});",
                '    logger.debug("first=" + r[0] + " count=" + r[1]);',
                f"    return TestUtil.check(logger, r[0] == {o3['FIRST']}, \"first R3.1 at \" + r[0] + \", expected {o3['FIRST']}\")",
                f"        && TestUtil.check(logger, r[1] == {o3['COUNT']}, \"R3.1 raise + repeats: \" + r[1] + \", expected {o3['COUNT']}\")",
                f"        && TestUtil.check(logger, r[0] - {o3['STOP']} <= 180, \"R3.1 later than 3 min after the stop\");", "}", "",
                # The same ride through the whole field: lifecycle, watchdog and alert delivery.
                "(:test)", "function replayOct3ThroughField(logger as Test.Logger) as Boolean {",
                f"    var r = Replay.fieldFirstAndTones(ReplayData.OCT3, {o3['WIN_END']});",
                f"    return TestUtil.check(logger, r[0] == {o3['FIRST']}, \"field: first alert at \" + r[0] + \", expected {o3['FIRST']}\")",
                f"        && TestUtil.check(logger, r[1] == {o3['COUNT']}, \"field: tones \" + r[1] + \", expected {o3['COUNT']}\");", "}", ""]
    if "OCT2" in rides:
        out += _silent_windows("OCT2", "Oct2", rides["OCT2"]["meta"]["SECONDS"])
    for name in sorted(n for n in rides if n.startswith("NOV")):
        meta, label = rides[name]["meta"], name.capitalize()
        out += ["(:test)", f"function replay{label}Life(logger as Test.Logger) as Boolean {{",
                f"    var n = Replay.lifeStarts(ReplayData.{name});",
                f"    return TestUtil.check(logger, n == {meta['STARTS']}, \"rides opened: \" + n + \", expected {meta['STARTS']}\");", "}", ""]
        out += _silent_windows(name, label, meta["SECONDS"])
    return "\n".join(out) + "\n"


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rides = {}
    if all(os.path.exists(p) for p in (OCT3_FIT, OCT2_FIT, OCT3_CSV)):
        s3, stop = series_oct3()
        win_end = min(len(s3), 330)        # first raise (~257 s) plus one repeat
        first, count = expected_alerts(s3[:win_end])
        rides["OCT3"] = {"packed": pack(rle(s3)), "meta": {"STOP": stop, "FIRST": first, "COUNT": count, "WIN_END": win_end}}
        s2, _ = series_oct2()
        rides["OCT2"] = {"packed": pack(rle(s2)), "meta": {"SECONDS": len(s2)}}
        print(f"OCT3: stop at +{stop} s, expected first R3.1 at +{first} s, {count} alerts in first {win_end} s; "
              f"OCT2: {len(s2)} s, {len(rle(s2))} segments")
    else:
        print("replay_gen: Oct ride backups not found; skipping those replays")
    if all(os.path.exists(p) for p in PROBE_LOGS):
        lines = []
        for p in PROBE_LOGS:
            lines += open(p, encoding="utf-8", errors="replace").read().splitlines()
        total = 0
        for ses in probe_sessions(lines):
            seq = probe_series(ses)
            if len(seq) < 60:              # a few seconds on the bench, not a ride
                continue
            name = f"NOV{sum(1 for n in rides if n.startswith('NOV')):02d}"
            rides[name] = {"packed": pack(rle(seq)), "meta": {"SECONDS": len(seq), "STARTS": expected_starts(seq)}}
            total += len(seq)
        print(f"NOV: {sum(1 for n in rides if n.startswith('NOV'))} probe sessions, {total} s")
    else:
        print("replay_gen: probe logs not found; skipping those replays")
    have = bool(rides)
    if not have:
        print("replay_gen: no ride data found; writing skip stubs")
    open(os.path.join(OUT_DIR, "ReplayData.mc"), "w").write(render_data(rides, have))
    open(os.path.join(OUT_DIR, "ReplayTestsGen.mc"), "w").write(render_tests(rides, have))
    return 0


if __name__ == "__main__":
    sys.exit(main())
