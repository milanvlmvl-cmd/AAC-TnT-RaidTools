import hashlib
import json
from pathlib import Path, PurePosixPath
import re

def relative_path(value):
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError("Use a nonempty forward-slash relative path.")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in value.split("/")):
        raise ValueError("Unsafe path.")
    if any(not re.fullmatch(r"[A-Za-z0-9_.-]+", part) for part in path.parts):
        raise ValueError("Unsafe filename.")
    return path

def load_project(root):
    root = Path(root).resolve()
    manifest = json.loads((root / "addon.json").read_text(encoding="utf-8"))
    if set(manifest) != {"id", "name", "author", "version", "runtime", "preserve"}:
        raise ValueError("Unexpected manifest fields.")
    if not re.fullmatch(r"[a-z][a-z0-9_]{2,39}", manifest["id"]):
        raise ValueError("Invalid addon ID.")
    base = root / "src" / manifest["id"]
    files = {}
    for item in manifest["runtime"]:
        name = str(relative_path(item))
        path = base / name
        if not name.endswith(".lua") or not path.is_file():
            raise ValueError("Runtime file missing or invalid.")
        files[name] = path.read_bytes()
    if "main.lua" not in files:
        raise ValueError("main.lua required.")
    return manifest, files

def digest(data):
    return hashlib.sha256(data).hexdigest()
