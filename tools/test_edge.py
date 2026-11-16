import edge
from edge import Entry, ROOT

TREE = {
    ROOT: [Entry(1, "Garmin", True, 0, 0)],
    1: [Entry(12, "Apps", True, 0, 0), Entry(22, "Activities", True, 0, 0)],
    12: [Entry(103, "LOGS", True, 0, 0), Entry(500, "RGSPIKE.PRG", False, 10, 0), Entry(826, "062E253.PRG", False, 9, 0)],
    103: [],
    22: [Entry(282, "2026-01-01-09-00-00.fit", False, 859714, 0)],
}
children = lambda pid: TREE.get(pid, [])

def test_resolve_is_case_insensitive():
    assert edge.resolve(children, "/GARMIN/apps/logs") == (103, True)
    assert edge.resolve(children, "/Garmin/Apps/RGSPIKE.PRG") == (500, False)

def test_resolve_missing_returns_none():
    assert edge.resolve(children, "/Garmin/Nope") is None

def test_write_allow_list():
    assert edge.is_write_allowed("/Garmin/Apps/RGSPIKE.PRG")
    assert edge.is_write_allowed("/Garmin/Apps/LOGS/rgspike.txt")
    assert edge.is_write_allowed("/Garmin/Apps/RIDEGRD.PRG")
    assert not edge.is_write_allowed("/Garmin/Apps/062E253.PRG")
    assert not edge.is_write_allowed("/Garmin/Activities/2026-01-01-09-00-00.fit")
    assert not edge.is_write_allowed("/Garmin/Apps/")

def test_put_replaces_existing_allowed_name():
    assert edge.plan_put(children, "/Garmin/Apps", "RGSPIKE.PRG") == (12, [500])
    assert edge.plan_put(children, "/Garmin/Apps/LOGS", "RGSPIKE.TXT") == (103, [])

def test_put_refuses_disallowed_name():
    import pytest
    with pytest.raises(PermissionError):
        edge.plan_put(children, "/Garmin/Apps", "062E253.PRG")

def test_put_refuses_missing_folder():
    import pytest
    with pytest.raises(FileNotFoundError):
        edge.plan_put(children, "/Garmin/NoSuchFolder", "RGSPIKE.PRG")

def _fake_device(listings):
    """A Device whose fake libmtp returns listings[(storage, parent)] = [(id, name, is_folder, storage_id)] as a linked list."""
    import ctypes as C
    made, freed = [], []

    class FakeLib:
        def LIBMTP_Get_Files_And_Folders(self, dev, storage, parent):
            items = listings.get((storage, parent), [])
            nodes = [edge._MTPFile() for _ in items]
            for i, (n, (iid, name, is_folder, sid, *size)) in enumerate(zip(nodes, items)):
                n.item_id, n.filename, n.storage_id = iid, name.encode(), sid
                n.filesize = size[0] if size else 0
                n.filetype = edge.FILETYPE_FOLDER if is_folder else 7
                n.next = C.pointer(nodes[i + 1]) if i + 1 < len(nodes) else None
            made.extend(nodes)
            return C.pointer(nodes[0]) if nodes else None

        def LIBMTP_destroy_file_t(self, p):
            freed.append(C.addressof(p.contents))

        def LIBMTP_Delete_Object(self, dev, item_id):
            self.deleted.append(item_id)
            return 0

        def LIBMTP_Send_File_From_File(self, dev, path, fileptr, cb, data):
            self.sent.append(path)
            return self.send_result

    d = edge.Device.__new__(edge.Device)
    d.lib, d.dev, d._storage = FakeLib(), None, {}
    d.lib.deleted, d.lib.sent, d.lib.send_result = [], [], 0
    return d, made, freed

def test_children_reads_and_frees_whole_list():
    import ctypes as C
    d, made, freed = _fake_device({(0, 1): [(10, "F0", True, 0), (11, "F1", False, 0), (12, "F2", False, 0)]})
    assert [(e.id, e.name, e.is_folder) for e in d.children(1)] == [(10, "F0", True), (11, "F1", False), (12, "F2", False)]
    assert sorted(freed) == sorted(C.addressof(n) for n in made)

def test_children_lists_subfolders_within_parent_storage():
    # The Edge lists its root for storage 0 (all storages) but returns nothing below the root unless given the real storage id.
    d, _, _ = _fake_device({
        (0, ROOT): [(1, "Garmin", True, 0x10001)],
        (0x10001, 1): [(12, "Apps", True, 0x10001)],
        (0x10001, 12): [(500, "RGSPIKE.PRG", False, 0x10001)],
    })
    assert edge.resolve(d.children, "/Garmin/Apps/RGSPIKE.PRG") == (500, False)

def test_put_to_apps_also_replaces_installed_copy_in_media():
    # The Edge installs a sideloaded PRG by moving it from Apps/ into Apps/Media/.
    tree = {
        ROOT: [Entry(1, "Garmin", True, 0, 0)],
        1: [Entry(12, "Apps", True, 0, 0)],
        12: [Entry(108, "Media", True, 0, 0), Entry(500, "RGSPIKE.PRG", False, 10, 0)],
        108: [Entry(600, "rgspike.prg", False, 10, 0), Entry(826, "062E253.PRG", False, 9, 0)],
    }
    assert edge.plan_put(lambda pid: tree.get(pid, []), "/Garmin/Apps", "RGSPIKE.PRG") == (12, [500, 600])

def test_put_checks_local_file_before_deleting_device_copy(tmp_path):
    import pytest
    d, _, _ = _fake_device({
        (0, ROOT): [(1, "Garmin", True, 0x10001)],
        (0x10001, 1): [(12, "Apps", True, 0x10001)],
        (0x10001, 12): [(500, "RGSPIKE.PRG", False, 0x10001)],
    })
    with pytest.raises(FileNotFoundError):
        d.put(str(tmp_path / "missing.prg"), "/Garmin/Apps", "RGSPIKE.PRG")
    assert d.lib.deleted == []


# --- Review fixes (2026-11-16): pick the Edge by USB id, keep pulled files inside the target folder ---

def test_pick_device_selects_the_edge_among_garmin_devices():
    # The Epix (091e:50da) is also an MTP device; writes must never go to it.
    assert edge.pick_device([(0x091E, 0x50DA), (0x091E, 0x5158)]) == 1
    assert edge.pick_device([(0x091E, 0x5158)]) == 0

def test_pick_device_refuses_when_only_another_device_is_connected():
    import pytest
    with pytest.raises(LookupError) as e:
        edge.pick_device([(0x091E, 0x50DA)])
    assert "091e:50da" in str(e.value) and "091e:5158" in str(e.value)

def test_pick_device_refuses_when_nothing_is_connected():
    import pytest
    with pytest.raises(LookupError):
        edge.pick_device([])

def test_local_path_maps_device_path_under_target(tmp_path):
    import os
    assert edge.local_path(str(tmp_path), "/Garmin/Apps/LOGS/RIDEGRD.TXT") == os.path.join(str(tmp_path), "Garmin", "Apps", "LOGS", "RIDEGRD.TXT")

def test_local_path_refuses_names_that_escape_the_target(tmp_path):
    import pytest
    # Object names come from the device. A name with "..", a separator or a NUL must not be joined into a local path.
    for bad in ("/Garmin/../../etc/passwd", "/../x", "/Garmin/Apps/..", "/Garmin/a\x00b", "/Garmin/./x", "/"):
        with pytest.raises(ValueError):
            edge.local_path(str(tmp_path), bad)

def test_failed_delete_is_reported_without_a_traceback(monkeypatch, capsys):
    d, _, _ = _fake_device({
        (0, ROOT): [(1, "Garmin", True, 0x10001)],
        (0x10001, 1): [(12, "Apps", True, 0x10001)],
        (0x10001, 12): [(500, "RGSPIKE.PRG", False, 0x10001)],
    })
    d.lib.LIBMTP_Delete_Object = lambda dev, item_id: 1          # the device refuses
    d.close = lambda: None
    monkeypatch.setattr(edge, "Device", lambda: d)
    import os, tempfile
    with tempfile.NamedTemporaryFile(suffix=".prg") as f:
        f.write(b"x"); f.flush()
        rc = edge.main(["put", f.name, "/Garmin/Apps", "RGSPIKE.PRG"])
    assert rc == 1
    assert "could not remove existing RGSPIKE.PRG" in capsys.readouterr().err


# --- Final review fixes: put must say when it leaves the Edge without the app ---

def _edge_with_app(size):
    return _fake_device({
        (0, ROOT): [(1, "Garmin", True, 0x10001)],
        (0x10001, 1): [(12, "Apps", True, 0x10001)],
        (0x10001, 12): [(500, "RIDEGRD.PRG", False, 0x10001, size)],
    })[0]

def test_put_succeeds_when_the_edge_lists_the_file_at_full_size(tmp_path):
    local = tmp_path / "RIDEGRD.prg"; local.write_bytes(b"x" * 7)
    d = _edge_with_app(7)
    assert d.put(str(local), "/Garmin/Apps", "RIDEGRD.PRG") is True
    assert d.lib.deleted == [500] and len(d.lib.sent) == 1

def test_put_failure_after_removing_the_old_copy_says_the_app_is_gone(tmp_path):
    import pytest
    local = tmp_path / "RIDEGRD.prg"; local.write_bytes(b"x" * 7)
    d = _edge_with_app(7)
    d.lib.send_result = 1                                        # cable pulled, Edge busy
    with pytest.raises(RuntimeError) as e:
        d.put(str(local), "/Garmin/Apps", "RIDEGRD.PRG")
    assert "NOT on the Edge" in str(e.value) and "old copy was removed" in str(e.value)

def test_put_checks_the_size_the_edge_reports_after_upload(tmp_path):
    import pytest
    local = tmp_path / "RIDEGRD.prg"; local.write_bytes(b"x" * 7)
    d = _edge_with_app(3)                                        # the Edge lists a short file
    with pytest.raises(RuntimeError) as e:
        d.put(str(local), "/Garmin/Apps", "RIDEGRD.PRG")
    assert "NOT on the Edge" in str(e.value)

def test_put_refuses_a_name_with_a_path_separator():
    import pytest
    for bad in ("x/RIDEGRD.PRG", "..\\RIDEGRD.PRG", "RIDEGRD/..", ".."):
        with pytest.raises(PermissionError):
            edge.plan_put(children, "/Garmin/Apps", bad)
