#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
reader_python="macos/.build/save-reader-venv/bin/python"
if [ ! -x "$reader_python" ]; then
  source_python="${FM_LAB_PYTHON:-python3}"
  "$source_python" -c 'import sys; assert sys.version_info >= (3, 11), "SaveReader requires Python 3.11+ for the build only"'
  "$source_python" -m venv macos/.build/save-reader-venv
  "$reader_python" -m pip install --cache-dir macos/.build/pip-cache -r requirements.txt pyinstaller==6.17.0
fi
export PYINSTALLER_CONFIG_DIR="$PWD/macos/.build/pyinstaller-cache"
"$reader_python" -m PyInstaller --noconfirm --onedir --name SaveReader --paths src \
  --collect-all fmsave --collect-all backports.zstd \
  --distpath macos/.build/save-reader-dist --workpath macos/.build/save-reader-work \
  --specpath macos/.build macos/runtime/SaveReader.py
"$reader_python" - <<'PY'
from importlib.metadata import distribution
from pathlib import Path
import shutil
target=Path('macos/.build/save-reader-dist/SaveReader/licenses')
target.mkdir(exist_ok=True)
for name in ('fmsave','backports-zstd','pyinstaller'):
    d=distribution(name)
    for f in d.files:
        if '/licenses/' in str(f):
            shutil.copy2(d.locate_file(f),target/(name+'-'+Path(f).name))
import sysconfig
license=Path(sysconfig.get_path('stdlib'))/'LICENSE.txt'
if license.exists():shutil.copy2(license,target/'Python-LICENSE.txt')
PY
