#!/usr/bin/env bash
# Build and sign a Connect IQ project.
#   tools/ciq-build.sh <project-dir> <out.prg> [device]   (device defaults to edge1050)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$here/ciq-env.sh"
if [[ $# -lt 2 ]]; then echo "usage: $0 <project-dir> <out.prg> [device]" >&2; exit 64; fi
proj="$1"; out="$2"; dev="${3:-edge1050}"
[[ -f "$CIQ_KEY" ]] || { echo "missing signing key $CIQ_KEY (see README.md, "Build it yourself")" >&2; exit 66; }
mkdir -p "$(dirname "$out")"
monkeyc -d "$dev" -f "$proj/monkey.jungle" -o "$out" -y "$CIQ_KEY" -w
echo "built $out"
