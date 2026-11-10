"""Cross-check Mac FMF envelopes with the unchanged Windows implementation.

Run with the SaveReader build venv (backports.zstd), output directory, helper,
and fm.app. All fixtures are generated in the supplied test directory.
"""
import json
from pathlib import Path
import struct
import subprocess
import sys
import time
from backports import zstd

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "src"))
import fm27_fmf


def main():
    folder, helper, app = map(Path, sys.argv[1:4])
    cases = sorted(folder.glob("formation-*/verified.fmf"))
    assert len(cases) == 12
    for fmf in cases:
        payload = fmf.read_bytes()
        plan = fm27_fmf.tactics_plan(payload)
        assert plan == fmf.with_name("tactic.tac").read_bytes()
    original = cases[0].read_bytes()
    content, end = fm27_fmf._zstd_frame(original, 26)
    details, _ = fm27_fmf._zstd_frame(original, end)
    chunks = [zstd.compress(content), zstd.compress(details)]
    title = "Windows envelope / Mac compressed read"
    now = int(time.time())

    def entry(name, extension, offset, chunk, raw):
        return fm27_fmf.string(name) + fm27_fmf.string(extension) + struct.pack("<QQQqq", offset, len(chunk), len(raw), now, now)

    toc = (fm27_fmf.string(title) + struct.pack("<I", 1)
           + entry(title, ".tac", 0, chunks[0], content)
           + struct.pack("<I", 1) + fm27_fmf.string("_data") + struct.pack("<I", 1)
           + entry("details", ".aom", len(chunks[0]), chunks[1], details) + struct.pack("<I", 0))
    body = b"".join(chunks)
    payload = fm27_fmf.HEADER + struct.pack("<QQB", 17 + len(body), 17, 3) + body + fm27_fmf.HEADER + zstd.compress(toc)
    path = folder / "compressed.fmf"
    path.write_bytes(payload)
    result = subprocess.run([str(helper), str(app), "--import-tactic", str(path.resolve())], capture_output=True, timeout=60)
    (folder / "compressed-read.jsonl").write_bytes(result.stdout)
    assert result.returncode == 0, result.stdout[-1000:]
    rows = [json.loads(line) for line in result.stdout.splitlines()]
    parsed = next(row for row in rows if row["event"] == "native_tactic_parsed")
    expected = json.loads(cases[0].with_name("verification.json").read_text())
    assert parsed["fields"] == expected["fields"] and parsed["name"] == title
    message = "PASS 12 Mac FMF envelopes accepted by unchanged upstream Windows parser; compressed FMF and compressed TOC accepted by original Mac archive driver"
    (folder / "archive-validation.txt").write_text(message)
    print(message)


if __name__ == "__main__":
    main()
