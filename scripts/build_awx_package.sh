#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO_ROOT/awx/awx_manifest.yml"
BUILD_DIR="$REPO_ROOT/build/awx_project"
OUT_TAR="$REPO_ROOT/build/awx_project.tar.gz"

mkdir -p "$BUILD_DIR"
rm -f "$OUT_TAR"

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST"
  exit 1
fi

# Copy each entry listed in the manifest into the build dir preserving structure
# Pass REPO_ROOT as an argument to the Python snippet so shell variables are not required inside the here-doc
python3 - "$REPO_ROOT" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = root / 'awx' / 'awx_manifest.yml'
if not manifest.exists():
    print(f"Manifest not found: {manifest}")
    raise SystemExit(1)

build = root / 'build' / 'awx_project'
build.mkdir(parents=True, exist_ok=True)
import yaml

data = yaml.safe_load(manifest.read_text()) or []
for entry in data:
    src = root / entry
    if not src.exists():
        print(f"Warning: manifest entry does not exist: {entry}")
        continue
    dst = build / entry
    if src.is_dir():
        import shutil
        shutil.copytree(src, dst, dirs_exist_ok=True)
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
print('Files copied to build/awx_project')
PY

# Create tar.gz
pushd "$REPO_ROOT/build" >/dev/null
rm -f awx_project.tar.gz
tar -czf awx_project.tar.gz awx_project
popd >/dev/null

echo "Created: $OUT_TAR"
exit 0
