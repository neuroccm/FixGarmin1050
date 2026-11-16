#!/usr/bin/env python3
"""Garmin Edge MTP dev helper (libmtp via ctypes).

Read operations are unrestricted. Writes/deletes are limited to file names that
start with an allow-listed prefix (our own dev artifacts) — never Garmin files.
Only the Edge 1050 (USB 091e:5158) is ever opened, so nothing can reach another
MTP device such as the Epix watch.
"""
import argparse
import ctypes as C
import json
import os
import subprocess
import sys
from collections import namedtuple

ROOT = 0xFFFFFFFF
FILETYPE_FOLDER = 0
FILETYPE_UNKNOWN = 44
WRITE_ALLOW_PREFIXES = ("RGSPIKE", "RIDEGRD")
EDGE_USB = (0x091E, 0x5158)             # Garmin Edge 1050
LIBMTP = "/opt/homebrew/lib/libmtp.dylib"

Entry = namedtuple("Entry", "id name is_folder size mtime")


def is_write_allowed(path):
    name = path.rstrip("/").split("/")[-1] if path.rstrip("/") else ""
    return bool(name) and not path.endswith("/") and name.upper().startswith(WRITE_ALLOW_PREFIXES)


def pick_device(ids, want=EDGE_USB):
    """Index of the Edge in `ids`, a list of (vendor_id, product_id) for the connected MTP devices."""
    for i, usb in enumerate(ids):
        if tuple(usb) == tuple(want):
            return i
    found = ", ".join(f"{v:04x}:{p:04x}" for v, p in ids) or "none"
    raise LookupError(f"no Edge 1050 ({want[0]:04x}:{want[1]:04x}) among the connected MTP devices ({found})")


def local_path(local_dir, device_path):
    """Local file for a device path, always inside local_dir. Object names come from the device, so a
    name that could climb out of local_dir ("..", a separator, a NUL) is refused."""
    parts = [p for p in device_path.split("/") if p]
    if not parts or any(p in (".", "..") or "\x00" in p or os.sep in p or "\\" in p for p in parts):
        raise ValueError(f"unsafe device path: {device_path!r}")
    root = os.path.realpath(local_dir)
    out = os.path.realpath(os.path.join(root, *parts))
    if os.path.commonpath([root, out]) != root:
        raise ValueError(f"unsafe device path: {device_path!r}")
    return os.path.join(local_dir, *parts)


def resolve(children, path):
    cur, is_folder = ROOT, True
    for part in [p for p in path.split("/") if p]:
        match = [e for e in children(cur) if e.name.lower() == part.lower()]
        if not match:
            return None
        cur, is_folder = match[0].id, match[0].is_folder
    return (cur, is_folder)


def plan_put(children, folder_path, name):
    if "/" in name or "\\" in name or name in (".", ".."):
        raise PermissionError(f"refusing to write {name!r}: a file name must not contain a path")
    if not is_write_allowed(folder_path.rstrip("/") + "/" + name):
        raise PermissionError(f"refusing to write {name!r}: not an allow-listed name {WRITE_ALLOW_PREFIXES}")
    found = resolve(children, folder_path)
    if not found or not found[1]:
        raise FileNotFoundError(f"device folder not found: {folder_path}")
    folder_id = found[0]
    dupes = [e.id for e in children(folder_id) if not e.is_folder and e.name.lower() == name.lower()]
    # The Edge installs a sideloaded PRG by moving it from Apps/ into Apps/Media/; replace that copy too.
    if [p.lower() for p in folder_path.split("/") if p] == ["garmin", "apps"]:
        media = resolve(children, folder_path.rstrip("/") + "/Media")
        if media and media[1]:
            dupes += [e.id for e in children(media[0]) if not e.is_folder and e.name.lower() == name.lower()]
    return folder_id, dupes


class _MTPFile(C.Structure):
    pass


class _DeviceEntry(C.Structure):
    _fields_ = [("vendor", C.c_char_p), ("vendor_id", C.c_uint16), ("product", C.c_char_p),
                ("product_id", C.c_uint16), ("device_flags", C.c_uint32)]


class _RawDevice(C.Structure):
    _fields_ = [("device_entry", _DeviceEntry), ("bus_location", C.c_uint32), ("devnum", C.c_uint8)]


_MTPFile._fields_ = [("item_id", C.c_uint32), ("parent_id", C.c_uint32), ("storage_id", C.c_uint32),
                     ("filename", C.c_char_p), ("filesize", C.c_uint64), ("modificationdate", C.c_long),
                     ("filetype", C.c_int), ("next", C.POINTER(_MTPFile))]


def quit_openmtp():
    if subprocess.run(["pgrep", "-x", "OpenMTP"], capture_output=True).returncode == 0:
        subprocess.run(["osascript", "-e", 'quit app "OpenMTP"'], capture_output=True)
        for _ in range(20):
            if subprocess.run(["pgrep", "-x", "OpenMTP"], capture_output=True).returncode != 0:
                break
            subprocess.run(["sleep", "0.5"])
        print("note: quit OpenMTP to free the device", file=sys.stderr)


class Device:
    def __init__(self):
        quit_openmtp()
        try:
            L = self.lib = C.CDLL(LIBMTP)
        except OSError:
            print(f"error: libmtp not found at {LIBMTP} — install it with: brew install libmtp", file=sys.stderr)
            sys.exit(2)
        L.LIBMTP_Detect_Raw_Devices.argtypes = [C.POINTER(C.c_void_p), C.POINTER(C.c_int)]
        L.LIBMTP_Open_Raw_Device_Uncached.restype = C.c_void_p
        L.LIBMTP_Open_Raw_Device_Uncached.argtypes = [C.c_void_p]
        L.LIBMTP_FreeMemory.argtypes = [C.c_void_p]
        L.LIBMTP_Get_Files_And_Folders.restype = C.POINTER(_MTPFile)
        L.LIBMTP_Get_Files_And_Folders.argtypes = [C.c_void_p, C.c_uint32, C.c_uint32]
        L.LIBMTP_Get_File_To_File.argtypes = [C.c_void_p, C.c_uint32, C.c_char_p, C.c_void_p, C.c_void_p]
        L.LIBMTP_Send_File_From_File.argtypes = [C.c_void_p, C.c_char_p, C.POINTER(_MTPFile), C.c_void_p, C.c_void_p]
        L.LIBMTP_Delete_Object.argtypes = [C.c_void_p, C.c_uint32]
        L.LIBMTP_Release_Device.argtypes = [C.c_void_p]
        L.LIBMTP_destroy_file_t.argtypes = [C.POINTER(_MTPFile)]
        L.LIBMTP_Init()
        # Open uncached: LIBMTP_Get_Files_And_Folders refuses a cached device (what LIBMTP_Get_First_Device returns).
        self._raw, n, self.dev, self._storage = C.c_void_p(), C.c_int(0), None, {}
        ids = []
        if L.LIBMTP_Detect_Raw_Devices(C.byref(self._raw), C.byref(n)) == 0 and n.value > 0:
            raws = C.cast(self._raw, C.POINTER(_RawDevice))
            ids = [(raws[i].device_entry.vendor_id, raws[i].device_entry.product_id) for i in range(n.value)]
        try:
            # Open the Edge and nothing else: the Epix is an MTP device too.
            which = pick_device(ids)
        except LookupError as e:
            print(f"error: {e} — is the Edge plugged in, and are OpenMTP/Garmin Express closed?", file=sys.stderr)
            sys.exit(2)
        self.dev = L.LIBMTP_Open_Raw_Device_Uncached(C.c_void_p(C.addressof(raws[which])))
        if not self.dev:
            print("error: could not open the Edge — are OpenMTP/Garmin Express closed?", file=sys.stderr)
            sys.exit(2)

    def close(self):
        self.lib.LIBMTP_Release_Device(self.dev)
        self.lib.LIBMTP_FreeMemory(self._raw)

    def children(self, parent_id):
        out, nodes = [], []
        # Storage 0 (all) only works at the root on the Edge; below it, list within the parent's own storage.
        p = self.lib.LIBMTP_Get_Files_And_Folders(self.dev, self._storage.get(parent_id, 0), parent_id)
        while p:
            c = p.contents
            self._storage[c.item_id] = c.storage_id
            out.append(Entry(c.item_id, (c.filename or b"").decode("utf-8", "replace"),
                             c.filetype == FILETYPE_FOLDER, int(c.filesize), int(c.modificationdate)))
            nodes.append(C.cast(p, C.c_void_p).value)  # copy the address: p may be a view into the previous node
            p = c.next
        for addr in nodes:  # destroy_file_t frees one node; it does not follow `next`
            self.lib.LIBMTP_destroy_file_t(C.cast(addr, C.POINTER(_MTPFile)))
        return out

    def walk(self, path):
        found = resolve(self.children, path)
        if not found:
            raise FileNotFoundError(path)
        base = "/" + "/".join(p for p in path.split("/") if p)
        if not found[1]:
            parent = resolve(self.children, os.path.dirname(base))
            e = [x for x in self.children(parent[0]) if x.id == found[0]][0]
            return [{"path": base, "id": e.id, "size": e.size, "mtime": e.mtime}]
        out, stack = [], [(found[0], base)]
        while stack:
            fid, fpath = stack.pop()
            for e in self.children(fid):
                p = f"{fpath}/{e.name}"
                if e.is_folder:
                    stack.append((e.id, p))
                else:
                    out.append({"path": p, "id": e.id, "size": e.size, "mtime": e.mtime})
        return sorted(out, key=lambda x: x["path"])

    def get(self, item_id, local):
        os.makedirs(os.path.dirname(os.path.abspath(local)), exist_ok=True)
        return self.lib.LIBMTP_Get_File_To_File(self.dev, item_id, local.encode(), None, None) == 0

    def put(self, local, folder_path, name):
        if not os.path.isfile(local):
            raise FileNotFoundError(f"local file not found: {local}")
        folder_id, dupes = plan_put(self.children, folder_path, name)
        for d in dupes:
            if self.lib.LIBMTP_Delete_Object(self.dev, d) != 0:
                raise RuntimeError(f"could not remove existing {name}")
        size = os.path.getsize(local)
        f = _MTPFile()
        f.filename = name.encode()
        f.filesize = size
        f.filetype = FILETYPE_UNKNOWN
        f.parent_id = folder_id
        f.storage_id = 0
        sent = self.lib.LIBMTP_Send_File_From_File(self.dev, local.encode(), C.byref(f), None, None) == 0
        # Believe the Edge's own listing, not the return code: the file must be there at full size.
        listed = [e.size for e in self.children(folder_id) if not e.is_folder and e.name.lower() == name.lower()]
        if sent and listed == [size]:
            return True
        gone = " The old copy was removed first." if dupes else ""
        raise RuntimeError(f"upload of {name} failed.{gone} {name} is NOT on the Edge now: run the command again")

    def rm(self, path):
        if not is_write_allowed(path):
            raise PermissionError(f"refusing to delete {path!r}: not an allow-listed name {WRITE_ALLOW_PREFIXES}")
        found = resolve(self.children, path)
        if not found or found[1]:
            raise FileNotFoundError(path)
        return self.lib.LIBMTP_Delete_Object(self.dev, found[0]) == 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ls").add_argument("path")
    sub.add_parser("tree").add_argument("path")
    g = sub.add_parser("get"); g.add_argument("path"); g.add_argument("local")
    pl = sub.add_parser("pull"); pl.add_argument("prefix"); pl.add_argument("local_dir"); pl.add_argument("--only-list")
    pu = sub.add_parser("put"); pu.add_argument("local"); pu.add_argument("folder"); pu.add_argument("name", nargs="?")
    sub.add_parser("rm").add_argument("path")
    a = ap.parse_args(argv)
    dev = Device()
    try:
        if a.cmd == "ls":
            found = resolve(dev.children, a.path)
            if not found:
                print(f"not found: {a.path}", file=sys.stderr); return 3
            for e in dev.children(found[0]):
                print(f"{'d' if e.is_folder else '-'} {e.size:>12} {e.mtime:>11} {e.name}")
        elif a.cmd == "tree":
            json.dump(dev.walk(a.path), sys.stdout, indent=1)
        elif a.cmd == "get":
            found = resolve(dev.children, a.path)
            if not found or found[1]:
                print(f"not found: {a.path}", file=sys.stderr); return 3
            return 0 if dev.get(found[0], a.local) else 1
        elif a.cmd == "pull":
            items = dev.walk(a.prefix)
            if a.only_list:
                wanted = {x["path"] for x in json.load(open(a.only_list))}
                items = [x for x in items if x["path"] in wanted]
            bad = 0
            for x in items:
                try:
                    local = local_path(a.local_dir, x["path"])
                except ValueError as e:
                    print(f"SKIP {e}"); bad += 1
                    continue
                ok = dev.get(x["id"], local) and os.path.getsize(local) == x["size"]
                bad += 0 if ok else 1
                print(("ok  " if ok else "FAIL") + f" {x['path']}")
            return 1 if bad else 0
        elif a.cmd == "put":
            name = a.name or os.path.basename(a.local)
            ok = dev.put(a.local, a.folder, name)
            print(("uploaded " if ok else "FAILED ") + f"{a.folder.rstrip('/')}/{name}")
            return 0 if ok else 1
        elif a.cmd == "rm":
            ok = dev.rm(a.path)
            print(("removed " if ok else "FAILED ") + a.path)
            return 0 if ok else 1
    except PermissionError as e:
        print(f"error: {e}", file=sys.stderr); return 3
    except FileNotFoundError as e:
        print(f"not found: {e}", file=sys.stderr); return 3
    except RuntimeError as e:
        print(f"error: {e}", file=sys.stderr); return 1
    finally:
        dev.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
