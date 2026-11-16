#!/usr/bin/env python3
"""Phase 0 analysis: find RGSpike storage blocks in pulled device files and summarise the spike log."""
import json
import os
import re
import sys

MAGIC = b"RGSPIKE!"
BLOCK = 4096
_FILL = bytes((j * 7) & 0xFF for j in range(10, BLOCK))
_RUN = _FILL[:64]


def expected_block(i):
    return MAGIC + bytes([i & 0xFF, (i >> 8) & 0xFF]) + _FILL


def scan(data):
    intact, damaged = set(), []
    off = data.find(MAGIC)
    while off != -1:
        if off + 10 <= len(data):
            i = data[off + 8] | (data[off + 9] << 8)
            if data[off:off + BLOCK] == expected_block(i):
                intact.add(i)
            else:
                damaged.append(off)
        off = data.find(MAGIC, off + 1)
    return {"intact": intact, "damaged": damaged, "fill_runs": data.count(_RUN)}


def diff_trees(before, after):
    old = {x["path"]: (x["size"], x["mtime"]) for x in before}
    return sorted([x for x in after if old.get(x["path"]) != (x["size"], x["mtime"])], key=lambda x: x["path"])


def parse_log(text):
    r = {"full_blocks": None, "alert": None, "tone": None, "computes": 0, "hidden_calls": 0,
         "not_on_calls": 0, "settings_view": False, "timer_events": []}
    for line in text.splitlines():
        msg = line.split(" ", 1)[1] if " " in line else line
        if m := re.match(r"FULL blocks=(\d+)", msg):
            r["full_blocks"] = int(m[1])
        elif msg.startswith("ALERT"):
            r["alert"] = msg
        elif msg.startswith("TONE"):
            r["tone"] = msg
        elif m := re.match(r"C n=(\d+) vis=\w+ timer=\S+ hid=(\d+) stop=(\d+)", msg):
            r["computes"], r["hidden_calls"], r["not_on_calls"] = int(m[1]), int(m[2]), int(m[3])
        elif msg.startswith("SETTINGSVIEW"):
            r["settings_view"] = True
        elif m := re.match(r"T (\w+)", msg):
            r["timer_events"].append(m[1])
    return r


def _jsonable(o):
    return sorted(o) if isinstance(o, set) else o


def main(argv):
    if len(argv) >= 2 and argv[0] == "scan":
        out = {}
        for p in argv[1:]:
            s = scan(open(p, "rb").read())
            out[p] = {"size": os.path.getsize(p), "intact": len(s["intact"]), "max_index": max(s["intact"], default=None),
                      "damaged": len(s["damaged"]), "fill_runs": s["fill_runs"]}
        json.dump(out, sys.stdout, indent=1, default=_jsonable); print(); return 0
    if len(argv) == 5 and argv[0] == "report":
        before, after = json.load(open(argv[1])), json.load(open(argv[2]))
        changed = diff_trees(before, after)
        files = []
        for x in changed:
            local = os.path.join(argv[3], x["path"].lstrip("/"))
            if os.path.exists(local):
                s = scan(open(local, "rb").read())
                verdict = "readable" if s["intact"] else ("present-but-unreadable" if x["size"] >= BLOCK else "no-blocks")
                files.append({**x, "intact": len(s["intact"]), "damaged": len(s["damaged"]),
                              "fill_runs": s["fill_runs"], "verdict": verdict})
            else:
                files.append({**x, "verdict": "not-pulled"})
        log = parse_log(open(argv[4], errors="replace").read()) if os.path.exists(argv[4]) else None
        json.dump({"changed_files": files, "log": log}, sys.stdout, indent=1, default=_jsonable); print(); return 0
    print("usage: spike_analyze.py scan <file>... | report <before.json> <after.json> <pulled-dir> <log-file>", file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
