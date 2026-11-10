import json
from pathlib import Path
import sys
from common import load_project

def check(root):
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as exc:
        raise ValueError("Install requirements-dev.txt first.") from exc
    root = Path(root).resolve()
    manifest, files = load_project(root)
    lua = LuaRuntime(unpack_returned_tuples=True, register_eval=False, register_builtins=False)
    compile_chunk = lua.eval("function(source, name, env) local c, e = loadstring(source, name); if not c then return nil, e end; setfenv(c, env); return c end")
    globals_ = lua.globals()
    env = lua.table()
    for name in ("ipairs", "pairs", "pcall", "tonumber", "tostring", "type", "math", "string", "table"):
        env[name] = globals_[name]
    env["_G"] = env
    env["ADDON_ID"], env["EXPECTED_NAME"] = manifest["id"], manifest["name"]
    env["EXPECTED_AUTHOR"], env["EXPECTED_VERSION"] = manifest["author"], manifest["version"]
    compiled, cache = {}, {}
    for name, content in files.items():
        value = compile_chunk(content.decode(), "@" + name, env)
        if isinstance(value, tuple): raise ValueError(value[1])
        compiled[manifest["id"] + "/" + name[:-4]] = value
    def require(name):
        if name not in cache:
            if name not in compiled: raise ValueError("Unexpected require: " + str(name))
            cache[name] = compiled[name]()
        return cache[name]
    env["require"] = require
    for name in compiled: require(name)
    addon = require(manifest["id"] + "/main")
    test_env = lua.table()
    for name in ("ipairs", "pairs", "pcall", "tonumber", "tostring", "type", "math", "string", "table", "assert", "error"):
        test_env[name] = globals_[name]
    for name in ("ADDON_ID", "EXPECTED_NAME", "EXPECTED_AUTHOR", "EXPECTED_VERSION", "require"):
        test_env[name] = env[name]
    test = compile_chunk((root / "tests/spec.lua").read_text(), "@tests/spec.lua", test_env)
    if isinstance(test, tuple): raise ValueError(test[1])
    return {"lua": "5.1", "runtime_files": len(files), "cases": int(test())}

if __name__ == "__main__":
    try: print("PASS", json.dumps(check(Path(__file__).resolve().parents[1]), sort_keys=True))
    except Exception as exc:
        print("CHECK FAILED:", exc, file=sys.stderr); sys.exit(1)
