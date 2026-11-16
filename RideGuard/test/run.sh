#!/usr/bin/env bash
# RideGuard test suite: regenerate replay tests from local ride backups, then run all unit tests.
set -euo pipefail
cd "$(dirname "$0")/../.."
tools/.venv/bin/python tools/replay_gen.py
tools/ciq-test.sh RideGuard/test.jungle RideGuard/bin/test.prg
