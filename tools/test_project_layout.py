"""Checks on the RideGuard project files that the Connect IQ toolchain won't make for us."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def jungle(name):
    text = open(os.path.join(ROOT, "RideGuard", name)).read()
    return dict(re.findall(r"^\s*([\w.]+)\s*=\s*(.+?)\s*$", text, flags=re.M))


def test_release_build_compiles_only_source():
    # The SDK default is `base.sourcePath = .\**.mc`: without this line the release build also
    # compiles test/ and test/generated/ (replay data derived from personal rides) into RIDEGRD.prg.
    assert jungle("monkey.jungle").get("base.sourcePath") == "source"


def test_test_build_adds_the_test_folder():
    assert jungle("test.jungle").get("base.sourcePath") == "source;test"
