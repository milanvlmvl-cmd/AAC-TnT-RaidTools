from io import BytesIO
import json
from pathlib import Path
import sys
import zipfile
from check import check
from common import digest, load_project

def build(root):
    root = Path(root).resolve()
    results = check(root)
    manifest, files = load_project(root)
    inputs = {"src/" + manifest["id"] + "/" + name: digest(data) for name, data in files.items()}
    for name in ("addon.json", "requirements-dev.txt", "tests/spec.lua", "tools/common.py", "tools/check.py", "tools/build.py"):
        inputs[name] = digest((root / name).read_bytes())
    source_digest = digest(json.dumps(inputs, sort_keys=True).encode())
    stream = BytesIO()
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(manifest["id"] + "/" + name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, files[name])
    payload = stream.getvalue()
    out = root / "dist"; out.mkdir(exist_ok=True)
    stem = manifest["id"] + "-" + manifest["version"] + "-" + source_digest[:12]
    zip_path = out / (stem + ".zip")
    with zip_path.open("xb") as output: output.write(payload)
    receipt = {"addon": manifest["id"], "version": manifest["version"], "source_sha256": source_digest,
               "zip_sha256": digest(payload), "inputs_sha256": inputs, "checks": results, "installed": False}
    (out / (stem + ".json")).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return zip_path

if __name__ == "__main__":
    try: print("Built:", build(Path(__file__).resolve().parents[1]))
    except Exception as exc:
        print("BUILD FAILED:", exc, file=sys.stderr); sys.exit(1)
