---
# Fill in the fields below to create a basic custom agent for your repository.
# The Copilot CLI can be used for local testing: https://gh.io/customagents/cli
# To make this agent available, merge this file into the default repository branch.
# For format details, see: https://gh.io/customagents/config

name: AAC Addon Dev
description: Develop .lua addons for archeage classic
---

# My Agent


Work from the player's current request. If they have an idea, propose one
small, testable first version and begin when the outcome is clear. If no idea
is given, ask what they want the addon to do or offer to start with the demo.
The demo has a manual counter and a button that reads the selected target's
name, current HP and maximum HP. It resets on reload.

The blocks below contain complete files. Extract them into a new addon project
when you can write files. For a new named addon, choose a unique folder ID and
update addon.json, the Lua folder, module paths and widget ID prefix together.
Keep main.lua's name, author and version in sync with addon.json.

If you can run commands, create a local Python environment, install the pinned
test dependency and run tools/check.py and tools/build.py. The build goes into
dist/. Use a fresh runtime ZIP for each changed build. If you can provide
downloadable files, give the player the ZIP. In a text-only chat, give complete,
named Lua files with the folder layout and installation steps. Tell the player
which checks you could actually run.

Use Lua 5.1 and the documented game interfaces. Keep gameplay-independent logic
in logic.lua and game reads and widgets in main.lua. Handle missing data, clean
up handlers and widgets on unload, and test one player action at a time.
You can find the available API in api.lua, in this repository. Any API-call not found in this file, is unavailable. 

For installation, the user installs the addon using a zip-folder and the addon manager bundled with the game.
The addon folder should contain main.lua directly. Add its folder ID to
addons.txt if needed and keep existing entries and settings. Ask before changing
the player's installed addons. Give them a short in-game checklist and the
expected result. The demo passed offline checks and still needs a native game
check. Only the runtime Lua files belong in the game ZIP.

STARTER PROJECT FILES

===== BEGIN FILE addon.json =====
{
  "id": "friend_addon_demo",
  "name": "Starter Demo",
  "author": "Your name",
  "version": "0.1.0",
  "runtime": ["main.lua", "logic.lua"],
  "preserve": []
}
===== END FILE addon.json =====

===== BEGIN FILE src/friend_addon_demo/main.lua =====
local Logic = require("friend_addon_demo/logic")
local addon = {
    name = "Starter Demo", author = "Your name", version = "0.1.0",
    desc = "Manual counter and target HP demo"
}
local state, generation = nil, 0
local call, get = Logic.call, Logic.get

local function log(api, text)
    call(get(api, "Log"), "Info", "[" .. addon.name .. "] " .. text)
end

local function dispose(s)
    if not s then return end
    s.live = false
    for i = #s.widgets, 1, -1 do
        local w = s.widgets[i]
        call(w, "StopMovingOrSizing")
        call(w, "Enable", false)
        for _, event in ipairs({"OnClick", "OnDragStart", "OnDragStop", "OnDragEnd"}) do
            call(w, "ReleaseHandler", event)
        end
        call(w, "Show", false)
        call(get(s.api, "Interface"), "Free", w)
    end
    s.widgets = {}
end

local function initialize(s, stamp)
    local function alive()
        return s.live and state == s and generation == stamp
    end
    local function place(w, parent, x, y, width, height)
        local a, ar = call(w, "SetExtent", width, height)
        local b, br = call(w, "RemoveAllAnchors")
        local c, cr = call(w, "AddAnchor", "TOPLEFT", parent, x, y)
        return a and ar ~= false and b and br ~= false and c and cr ~= false
    end
    local function make(kind, id, parent, x, y, width, height, text)
        local ok, w = call(get(s.api, "Interface"), "CreateWidget", kind,
            "friend_addon_demo_" .. id, parent)
        if not ok or not w then return nil end
        s.widgets[#s.widgets + 1] = w
        if not place(w, parent, x, y, width, height) then return nil end
        if text then call(w, "SetText", text) end
        call(get(w, "style"), "SetFontSize", 14)
        call(get(w, "style"), "SetColor", .94, .96, .95, 1)
        call(w, "Show", true)
        return w
    end
    local function paint(w, width, height, r, g, b)
        -- Colour drawables belong to their parent; do not free them separately.
        local ok, d = call(w, "CreateColorDrawable", r, g, b, .98, "background")
        if ok and d then place(d, w, 0, 0, width, height); call(d, "Show", true) end
    end
    local root = make("window", "window", "UIParent", 160, 180, 380, 240)
    if not root then return false end
    s.root = root
    paint(root, 380, 240, .055, .075, .085)
    local function button(id, text, x, y, width, fn)
        local w = make("button", id, root, x, y, width, 30, text)
        if not w then return nil end
        paint(w, width, 30, .16, .24, .27)
        local ok, result = call(w, "SetHandler", "OnClick", function()
            if alive() then fn() end
        end)
        if not ok or result == false then return nil end
        return w
    end
    local title = button("title", addon.name, 12, 10, 310, function() end)
    local close = button("close", "X", 334, 10, 34, function() call(root, "Show", false) end)
    local count = make("label", "count", root, 12, 53, 356, 30, "Count: 0")
    local target = make("label", "target", root, 12, 136, 356, 24, "Choose a target, then Read target.")
    local health = make("label", "health", root, 12, 162, 356, 24, "HP: unavailable")
    local hint = make("label", "hint", root, 12, 203, 356, 22, "Drag title. Settings cog reopens. No saves.")
    if not title or not close or not count or not target or not health or not hint then return false end
    call(get(hint, "style"), "SetFontSize", 12)
    local function change(delta)
        local value = Logic.step(s.count, delta)
        if value ~= nil then s.count = value; call(count, "SetText", "Count: " .. value) end
    end
    local minus = button("minus", "-", 12, 93, 70, function() change(-1) end)
    local plus = button("plus", "+", 92, 93, 70, function() change(1) end)
    local read = button("read", "Read target", 174, 93, 194, function()
        local snapshot, why = Logic.readTarget(get(s.api, "Unit"))
        if snapshot then
            call(target, "SetText", snapshot.name)
            call(health, "SetText", "HP: " .. snapshot.hp .. " / " .. snapshot.maximum)
        else
            call(target, "SetText", why)
            call(health, "SetText", "HP: unavailable")
        end
    end)
    if not minus or not plus or not read then return false end
    call(title, "EnableDrag", true)
    call(title, "SetHandler", "OnDragStart", function()
        if alive() then call(root, "StartMoving") end
    end)
    local function stop()
        if alive() then call(root, "StopMovingOrSizing") end
    end
    call(title, "SetHandler", "OnDragStop", stop)
    call(title, "SetHandler", "OnDragEnd", stop)
    return true
end

function addon.OnLoad()
    dispose(state)
    generation = generation + 1
    local ok, api = pcall(require, "api")
    if not ok or not api then state = nil; return end
    if Logic.version ~= addon.version then
        state = nil
        log(api, "Helper version differs. Restart the game after updating both files.")
        return
    end
    local s = {api = api, widgets = {}, count = 0, live = true}
    state = s
    local worked, result = pcall(initialize, s, generation)
    if not worked or result ~= true then
        dispose(s); state = nil
        log(api, "Could not build the demo window. Native UI check needed.")
    end
end

function addon.OnSettingToggle()
    if state and state.live then call(state.root, "Show", true) end
end

function addon.OnUnload()
    local previous = state
    state = nil
    generation = generation + 1
    dispose(previous)
end

return addon
===== END FILE src/friend_addon_demo/main.lua =====

===== BEGIN FILE src/friend_addon_demo/logic.lua =====
-- Original, independent logic. No widgets, events or work at import time.
local M = {version = "0.1.0"}

function M.get(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end

function M.call(object, method, ...)
    local fn = M.get(object, method)
    if type(fn) ~= "function" then return false, "unavailable" end
    return pcall(fn, object, ...)
end

local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value <= 9007199254740991 and value == math.floor(value)
end

function M.step(count, change)
    if not integer(count) or count > 9999 or (change ~= -1 and change ~= 1) then
        return nil, "Invalid counter value."
    end
    return math.max(0, math.min(9999, count + change))
end

local function present(id)
    if type(id) == "string" then return id ~= "" and id ~= "0" end
    return integer(id) and id > 0
end

function M.readTarget(unit)
    local ok, id = M.call(unit, "GetUnitId", "target")
    if not ok or not present(id) then return nil, "No selected target." end
    local a, name = M.call(unit, "UnitName", "target")
    local b, hp = M.call(unit, "UnitHealth", "target")
    local c, maximum = M.call(unit, "UnitMaxHealth", "target")
    local d, again = M.call(unit, "GetUnitId", "target")
    if not d or id ~= again then return nil, "Target changed; read again." end
    if not a or type(name) ~= "string" or name == "" or #name > 160
        or not b or not c or not integer(hp) or not integer(maximum)
        or maximum == 0 or hp > maximum then
        return nil, "Target data unavailable."
    end
    return {name = name, hp = hp, maximum = maximum}
end

return M
===== END FILE src/friend_addon_demo/logic.lua =====

===== BEGIN FILE tests/spec.lua =====
local Logic = require(ADDON_ID .. "/logic")
local addon = require(ADDON_ID .. "/main")
local cases = 0
local function test(name, fn)
    local ok, why = pcall(fn)
    if not ok then error(name .. ": " .. tostring(why)) end
    cases = cases + 1
end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end

test("counter boundaries and validation", function()
    equal(Logic.step(0, -1), 0); equal(Logic.step(0, 1), 1)
    equal(Logic.step(9999, 1), 9999); equal(Logic.step(1, -1), 0)
    equal(Logic.step(-1, 1), nil); equal(Logic.step(0 / 0, 1), nil)
    equal(Logic.step(1.5, 1), nil); equal(Logic.step(2, 100), nil)
end)

local function unit(hp, maximum)
    return {GetUnitId = function() return "target-A" end,
        UnitName = function() return "Example target" end,
        UnitHealth = function() return hp end, UnitMaxHealth = function() return maximum end}
end
test("valid target including zero current HP", function()
    local snapshot = Logic.readTarget(unit(0, 100))
    equal(snapshot.hp, 0); equal(snapshot.maximum, 100)
end)
test("missing APIs, missing target and errors stay unavailable", function()
    equal(Logic.readTarget(nil), nil); equal(Logic.readTarget({}), nil)
    local u = unit(1, 2); u.GetUnitId = function() return "0" end
    equal(Logic.readTarget(u), nil)
    u = unit(1, 2); u.UnitHealth = function() error("native read failed") end
    equal(Logic.readTarget(u), nil)
end)
test("changed target rejects mixed snapshot", function()
    local u, calls = unit(1, 2), 0
    u.GetUnitId = function() calls = calls + 1; return calls == 1 and "A" or "B" end
    equal(Logic.readTarget(u), nil)
end)
test("invalid numbers never become valid HP", function()
    for _, values in ipairs({{2, 1}, {-1, 2}, {1, 0}, {1, math.huge}, {1, .5}, {0 / 0, 2}}) do
        equal(Logic.readTarget(unit(values[1], values[2])), nil)
    end
end)

-- UI stub models ownership and handler lifetime, not native appearance.
local widgets, frees, created, failAt, failureMode = {}, 0, 0, nil, nil
local function widget(id, parent)
    local w = {id = id, parent = parent, handlers = {}, shown = false, text = "", moving = false}
    w.style = {SetColor = function() end, SetFontSize = function() end}
    function w:SetExtent() end
    function w:RemoveAllAnchors() end
    function w:AddAnchor() end
    function w:SetText(value) assert(not self.freed); self.text = value end
    function w:Show(value) self.shown = value end
    function w:Enable(value) self.enabled = value end
    function w:EnableDrag(value) self.drag = value end
    function w:SetHandler(event, fn) self.handlers[event] = fn end
    function w:ReleaseHandler(event) self.handlers[event] = nil end
    function w:StartMoving() self.moving = true end
    function w:StopMovingOrSizing() self.moving = false end
    function w:CreateColorDrawable() return widget("drawable", self) end
    return w
end
local api = {Unit = unit(42, 100), Log = {Info = function() end}, Interface = {}}
function api.Interface:CreateWidget(kind, id, parent)
    created = created + 1
    if created == failAt then
        if failureMode == "throw" then error("creation failed") end
        return nil
    end
    local w = widget(id, parent); widgets[#widgets + 1] = w; return w
end
function api.Interface:Free(w)
    assert(not w.freed, "double free"); w.freed = true; frees = frees + 1
end
local oldRequire = RUNTIME.require
RUNTIME.require = function(name) if name == "api" then return api end; return oldRequire(name) end
local function byId(suffix)
    local id = ADDON_ID .. "_" .. suffix
    for i = #widgets, 1, -1 do if widgets[i].id == id and not widgets[i].freed then return widgets[i] end end
    error("missing widget " .. suffix)
end
local function click(id) local w = byId(id); w.handlers.OnClick(w, "LeftButton") end

test("inert import and matching metadata", function()
    equal(#widgets, 0); equal(addon.name, EXPECTED_NAME)
    equal(addon.author, EXPECTED_AUTHOR); equal(addon.version, EXPECTED_VERSION)
end)
test("load, counter and selected target UI", function()
    addon.OnLoad(); assert(byId("window").shown)
    click("minus"); equal(byId("count").text, "Count: 0")
    click("plus"); equal(byId("count").text, "Count: 1")
    click("read"); equal(byId("health").text, "HP: 42 / 100")
    api.Unit = {}; click("read"); equal(byId("health").text, "HP: unavailable")
end)
test("close, settings reopen and title drag", function()
    click("close"); equal(byId("window").shown, false)
    addon.OnSettingToggle(); equal(byId("window").shown, true)
    local title, root = byId("title"), byId("window")
    title.handlers.OnDragStart(title); equal(root.moving, true)
    title.handlers.OnDragEnd(title); equal(root.moving, false)
end)
test("unload frees only owned widgets; stale handlers do nothing", function()
    local oldClick, oldDrag = byId("plus").handlers.OnClick, byId("title").handlers.OnDragStart
    local oldCount, oldRoot = byId("count"), byId("window")
    addon.OnUnload(); equal(frees, #widgets)
    oldClick(); oldDrag(); equal(oldCount.text, "Count: 1"); equal(oldRoot.moving, false)
    local before = frees; addon.OnUnload(); equal(frees, before)
end)
test("reload invalidates old handlers and creates one live window", function()
    addon.OnLoad(); local stale = byId("plus").handlers.OnClick
    addon.OnLoad(); stale(); equal(byId("count").text, "Count: 0")
    local live = 0
    for _, w in ipairs(widgets) do if w.id == ADDON_ID .. "_window" and not w.freed then live = live + 1 end end
    equal(live, 1); addon.OnUnload()
end)
test("partial startup and thrown native creation clean up", function()
    for _, mode in ipairs({"nil", "throw"}) do
        failAt = created + 4; failureMode = mode
        addon.OnLoad(); addon.OnUnload(); equal(frees, #widgets)
    end
    failAt = nil
end)
test("missing interface and mismatched cached helper are inactive", function()
    local previous = api.Interface; api.Interface = nil
    addon.OnLoad(); addon.OnUnload(); equal(frees, #widgets); api.Interface = previous
    local version = Logic.version; Logic.version = "old"
    local before = created; addon.OnLoad(); equal(created, before); Logic.version = version
end)
RUNTIME.require = oldRequire
return cases
===== END FILE tests/spec.lua =====

===== BEGIN FILE requirements-dev.txt =====
# Development only. No Python or third-party dependency ships in the game ZIP.
lupa==2.8
===== END FILE requirements-dev.txt =====

===== BEGIN FILE tools/common.py =====
"""Small exact-allowlist packaging policy; no game access."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re


def relative_path(value):
    if not isinstance(value, str) or not value or "\\" in value:
        raise ValueError("Use a nonempty forward-slash relative path.")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in value.split("/")):
        raise ValueError("Absolute paths and traversal are not allowed.")
    for part in path.parts:
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", part) or part.endswith((".", " ")):
            raise ValueError("Unsafe filename in manifest.")
        if part.split(".")[0].upper() in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}:
            raise ValueError("Reserved Windows filename.")
    return path


def load_project(root):
    root = Path(root).resolve()
    manifest = json.loads((root / "addon.json").read_text(encoding="utf-8"))
    if set(manifest) != {"id", "name", "author", "version", "runtime", "preserve"}:
        raise ValueError("Unexpected or missing manifest fields.")
    if not isinstance(manifest["id"], str) or not re.fullmatch(r"[a-z][a-z0-9_]{2,39}", manifest["id"]):
        raise ValueError("Invalid addon ID.")
    for field, limit in (("name", 24), ("author", 40)):
        value = manifest[field]
        if not isinstance(value, str) or not value.strip() or len(value) > limit or any(ord(c) < 32 or ord(c) > 126 for c in value):
            raise ValueError(f"Invalid {field}.")
    if not isinstance(manifest["version"], str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", manifest["version"]):
        raise ValueError("Use a three-number version, for example 0.1.0.")
    if not isinstance(manifest["runtime"], list) or not manifest["runtime"] or not isinstance(manifest["preserve"], list):
        raise ValueError("runtime and preserve must be lists; runtime cannot be empty.")
    preserve = {str(relative_path(p)).casefold() for p in manifest["preserve"]}
    base = root / "src" / manifest["id"]
    if base.is_symlink() or not base.is_dir() or not base.resolve().is_relative_to(root):
        raise ValueError("Runtime source folder must stay inside the project.")
    files, seen = {}, set()
    for item in manifest["runtime"]:
        name = str(relative_path(item))
        if name.casefold() in seen or name.casefold() in preserve:
            raise ValueError("Duplicate runtime path or collision with preserved settings.")
        seen.add(name.casefold())
        if not name.endswith(".lua") or any(word in name.casefold() for word in ("preferences", "saved_variables", "settings_save")):
            raise ValueError("Only reviewed Lua runtime files; exclude saved preferences.")
        path = base / name
        if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(base.resolve()):
            raise ValueError("Runtime file missing or outside its source folder.")
        files[name] = path.read_bytes()
    if "main.lua" not in files:
        raise ValueError("main.lua must be explicitly listed.")
    return manifest, files


def digest(data):
    return hashlib.sha256(data).hexdigest()
===== END FILE tools/common.py =====

===== BEGIN FILE tools/check.py =====
"""Compile and exercise trusted addon source with Lua 5.1 and a mock UI."""
import json
from pathlib import Path
import sys
from common import load_project


def check(root):
    try:
        from lupa.lua51 import LuaRuntime
    except ImportError as exc:
        raise ValueError("Lua 5.1 checks unavailable. Install requirements-dev.txt in a project-local Python environment.") from exc
    root = Path(root).resolve()
    manifest, files = load_project(root)
    lua = LuaRuntime(unpack_returned_tuples=True, register_eval=False, register_builtins=False)
    compile_chunk = lua.eval("""function(source, name, env)
        local chunk, message = loadstring(source, name)
        if not chunk then return nil, message end
        setfenv(chunk, env)
        return chunk
    end""")
    globals_ = lua.globals()
    env = lua.table()
    for name in ("ipairs", "pairs", "pcall", "tonumber", "tostring", "type", "math", "string", "table"):
        env[name] = globals_[name]
    env["_G"] = env
    env["ADDON_ID"] = manifest["id"]
    env["EXPECTED_VERSION"] = manifest["version"]
    env["EXPECTED_NAME"] = manifest["name"]
    env["EXPECTED_AUTHOR"] = manifest["author"]
    compiled, cache, loading = {}, {}, set()
    for name, content in files.items():
        value = compile_chunk(content.decode("utf-8"), "@" + name, env)
        if isinstance(value, tuple):
            raise ValueError(f"Lua syntax error in {name}: {value[1]}")
        compiled[manifest["id"] + "/" + name[:-4]] = value

    def require(name):
        if name in cache:
            return cache[name]
        if name not in compiled or name in loading:
            raise ValueError("Unexpected or circular require: " + str(name))
        loading.add(name)
        try:
            cache[name] = compiled[name]()
        finally:
            loading.remove(name)
        return cache[name]

    # Game APIs do not exist during imports. Any import-time native work fails.
    env["require"] = require
    for name in compiled:
        require(name)
    addon = require(manifest["id"] + "/main")
    for field in ("name", "author", "version"):
        if addon[field] != manifest[field]:
            raise ValueError("Lua metadata differs from addon.json: " + field)
    description = addon["desc"]
    if not isinstance(description, str) or not description or len(description) > 42 or "\n" in description or "\r" in description:
        raise ValueError("Use a short single-line addon description (42 characters maximum).")
    # Assertion/throw are available only to test code, not the compiled runtime.
    test_env = lua.table()
    for name in ("ipairs", "pairs", "pcall", "tonumber", "tostring", "type", "math", "string", "table", "assert", "error"):
        test_env[name] = globals_[name]
    for name in ("ADDON_ID", "EXPECTED_VERSION", "EXPECTED_NAME", "EXPECTED_AUTHOR", "require"):
        test_env[name] = env[name]
    test_env["RUNTIME"] = env
    test_chunk = compile_chunk((root / "tests" / "spec.lua").read_text(encoding="utf-8"), "@tests/spec.lua", test_env)
    if isinstance(test_chunk, tuple):
        raise ValueError("Test syntax error: " + str(test_chunk[1]))
    cases = test_chunk()
    if not isinstance(cases, (int, float)) or cases < 1:
        raise ValueError("The test spec did not report a positive case count.")
    return {"lua": "5.1", "runtime_files": len(files), "cases": int(cases), "native_tested": False}


if __name__ == "__main__":
    try:
        print("PASS", json.dumps(check(Path(__file__).resolve().parents[1]), sort_keys=True))
    except Exception as exc:
        print("CHECK FAILED:", exc, file=sys.stderr)
        sys.exit(1)
===== END FILE tools/check.py =====

===== BEGIN FILE tools/build.py =====
"""Check, then build an immutable game-only ZIP and exact source receipt."""
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
    source_digest = digest(json.dumps(inputs, sort_keys=True).encode("utf-8"))
    stream = BytesIO()
    with zipfile.ZipFile(stream, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(manifest["id"] + "/" + name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, files[name])
    payload = stream.getvalue()
    out = root / "dist"
    if out.is_symlink() or (out.exists() and not out.resolve().is_relative_to(root)):
        raise ValueError("Build output must stay inside this project.")
    out.mkdir(exist_ok=True)
    stem = f"{manifest['id']}-{manifest['version']}-{source_digest[:12]}"
    zip_path, receipt_path = out / (stem + ".zip"), out / (stem + ".json")
    if zip_path.exists() or receipt_path.exists():
        raise ValueError("This immutable build already exists; nothing was overwritten.")
    receipt = {"addon": manifest["id"], "version": manifest["version"], "source_sha256": source_digest,
               "zip_sha256": digest(payload), "inputs_sha256": inputs, "checks": results,
               "installed": False, "preserved_paths": manifest["preserve"]}
    with zip_path.open("xb") as output:  2
  3
  4
  5
  6
  7
  8
  9
 10
 11
 12
 13
---
# Fill in the fields below to create a basic custom agent for your repository.
# The Copilot CLI can be used for local testing: https://gh.io/customagents/cli
# To make this agent available, merge this file into the default repository branch.
# For format details, see: https://gh.io/customagents/config

name:
description:
---

# My Agent

Describe what your agent does here.
        output.write(payload)
    with receipt_path.open("x", encoding="utf-8", newline="\n") as output:
        output.write(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return zip_path


if __name__ == "__main__":
    try:
        print("Built:", build(Path(__file__).resolve().parents[1]))
    except Exception as exc:
        print("BUILD FAILED:", exc, file=sys.stderr)
        sys.exit(1)
===== END FILE tools/build.py =====
