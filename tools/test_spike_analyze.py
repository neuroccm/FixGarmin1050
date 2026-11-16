import random
import spike_analyze as sa


def test_scan_counts_intact_blocks_in_container():
    data = b"HDR" * 10 + sa.expected_block(0) + b"\x00" * 33 + sa.expected_block(1) + sa.expected_block(2) + b"TAIL"
    r = sa.scan(data)
    assert r["intact"] == {0, 1, 2}
    assert r["damaged"] == []
    assert r["fill_runs"] > 0


def test_scan_flags_damaged_block():
    blk = bytearray(sa.expected_block(5)); blk[2000] ^= 0xFF
    r = sa.scan(bytes(blk) + sa.expected_block(6))
    assert r["intact"] == {6}
    assert len(r["damaged"]) == 1


def test_scan_scrambled_is_unreadable():
    rnd = random.Random(1)
    plain = b"".join(sa.expected_block(i) for i in range(4))
    scrambled = bytes(b ^ rnd.randrange(256) for b in plain)
    r = sa.scan(scrambled)
    assert r["intact"] == set() and r["fill_runs"] == 0


def test_diff_trees_reports_new_and_changed():
    before = [{"path": "/Garmin/Apps/A", "size": 1, "mtime": 10}, {"path": "/Garmin/Apps/B", "size": 2, "mtime": 10}]
    after = [{"path": "/Garmin/Apps/A", "size": 1, "mtime": 10}, {"path": "/Garmin/Apps/B", "size": 3, "mtime": 11},
             {"path": "/Garmin/Apps/DATA/RGSPIKE.DAT", "size": 140000, "mtime": 12}]
    assert [x["path"] for x in sa.diff_trees(before, after)] == ["/Garmin/Apps/B", "/Garmin/Apps/DATA/RGSPIKE.DAT"]


def test_parse_log():
    log = "\n".join([
        "1790000000 INIT done=null",
        "1790000010 C n=10 vis=true timer=0 hid=0 stop=10 fill 4",
        "1790000020 ALERT shown",
        "1790000020 TONE-ERR Permission denied",
        "1790000040 FULL blocks=31",
        "1790000060 C n=60 vis=false timer=3 hid=25 stop=50 full@31",
        "1790000061 T start",
        "1790000099 SETTINGSVIEW opened",
    ])
    r = sa.parse_log(log)
    assert r["full_blocks"] == 31
    assert r["alert"] == "ALERT shown"
    assert r["tone"] == "TONE-ERR Permission denied"
    assert (r["computes"], r["hidden_calls"], r["not_on_calls"]) == (60, 25, 50)
    assert r["settings_view"] is True
    assert r["timer_events"] == ["start"]
