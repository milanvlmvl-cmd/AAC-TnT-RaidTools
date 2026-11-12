local api = require("api")
local constants = require("AAC-TnT-RaidTools/core/constants")
local trace = require("AAC-TnT-RaidTools/core/trace")
local Guard = require("AAC-TnT-RaidTools/core/guard")
local Roles = require("AAC-TnT-RaidTools/features/roles")

-- "Save GS+Class": real scanned values are kept on disk (constants.raidSort.playersFolder, one .dat
-- file per player) and used for a player whose class or gear score cannot be read right now
-- (out of range). Files written by the dump test mode have the same className / gearScore fields.
local PlayerStore = {}

local folder = constants.raidSort.playersFolder
local log = trace.Logger("playerstore")
local safe = Guard.New(log)

local savedOnDisk = {} -- name -> {class, gs} last written or read, so unchanged values are not rewritten
local diskChecked = {} -- name -> true once the folder was checked for them this load
local liveClass, liveGs = {}, {} -- name -> value actually read from the game in this raid (never from disk)
local savedThisRaid = {} -- name -> true once their file was written for this raid

function PlayerStore.Path(name)
    return folder .. "/" .. (name:gsub("[^%w_%-]", "_")) .. ".dat"
end

-- Class and gear score from the player's file (nil, nil when there is none).
local function load(name)
    diskChecked[name] = true
    local record = safe("File:Read", function() return api.File:Read(PlayerStore.Path(name)) end)
    if type(record) ~= "table" then return nil, nil end
    local class, gs = Roles.ClassName(record.className), Roles.ToGearScore(record.gearScore)
    savedOnDisk[name] = {class = class, gs = gs}
    return class, gs
end

local function save(name, class, gs)
    local last = savedOnDisk[name]
    if last ~= nil and last.class == class and last.gs == gs then return true end -- file already has these values
    local record = {name = name, className = class, gearScore = gs}
    local ok = safe("File:Write", function() api.File:Write(PlayerStore.Path(name), record) return true end)
    if ok then
        savedOnDisk[name] = {class = class, gs = gs}
        log("saved " .. name .. ": " .. tostring(class) .. " gs=" .. tostring(gs))
    end
    return ok and true or false
end

-- The player's file, read at most once per load: class, gear score (nil, nil when none or already read).
function PlayerStore.Lookup(name)
    if diskChecked[name] then return nil, nil end
    return load(name)
end

-- Report what was read live from the game for a player (nil for what could not be read; cached and
-- disk values must never be passed in). Once both class and gear score have been read live in this
-- raid they are written, once; the file is not touched again until PlayerStore.NewRaid().
function PlayerStore.Observe(name, class, gs)
    if class ~= nil then liveClass[name] = class end
    if gs ~= nil then liveGs[name] = gs end
    if not savedThisRaid[name] and liveClass[name] ~= nil and liveGs[name] ~= nil then
        if save(name, liveClass[name], liveGs[name]) then savedThisRaid[name] = true end
    end
end

-- A new raid starts when the raid is left or disbanded (nobody but you left): everyone may be saved once more.
function PlayerStore.NewRaid()
    liveClass, liveGs, savedThisRaid = {}, {}, {}
end

-- Look in the files again (the setting was switched on).
function PlayerStore.ForgetChecked()
    diskChecked = {}
end

-- Forget everything held in memory (addon load).
function PlayerStore.Reset()
    savedOnDisk, diskChecked = {}, {}
    PlayerStore.NewRaid()
end

return PlayerStore
