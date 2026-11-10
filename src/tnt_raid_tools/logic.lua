local M = {
    version = "0.1.0",
    channelIds = {
        nation = -2,
        faction = -1,
        guild = 6,
        whisper = -3
    }
}

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

local function clean(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.normalizeName(value)
    return clean(value):lower()
end

function M.splitNames(value)
    local result, seen = {}, {}
    for item in (tostring(value or "") .. ","):gmatch("([^,]*),") do
        local name = clean(item)
        local key = M.normalizeName(name)
        if name ~= "" and not seen[key] then
            result[#result + 1], seen[key] = name, true
        end
    end
    return result
end

function M.lookup(names)
    local result = {}
    for _, name in ipairs(names or {}) do
        local key = M.normalizeName(name)
        if key ~= "" then result[key] = true end
    end
    return result
end

function M.matchesPhrase(message, phrase, mode)
    message, phrase = M.normalizeName(message), M.normalizeName(phrase)
    if phrase == "" then return false end
    if mode == "equals" then return message == phrase end
    if mode == "starts" then return message:sub(1, #phrase) == phrase end
    return message:find(phrase, 1, true) ~= nil
end

function M.channelAllowed(channelId, selection)
    if selection == "all" then return true end
    return M.channelIds[selection] == channelId
end

function M.eligible(message, channelId, config, blacklist, whitelist)
    if not config.enabled or not M.channelAllowed(channelId, config.channel) then return false end
    local nameKey = M.normalizeName(message.name)
    if nameKey == "" or blacklist[nameKey] then return false end
    if config.whitelistEnabled and not whitelist[nameKey] then return false end
    return M.matchesPhrase(message.text, config.phrase, config.match)
end

function M.passLead(team, name, log)
    if type(name) ~= "string" or name == "" then return false, "missing name" end
    local ok, index = M.call(team, "GetMemberIndexByName", name)
    if not ok or not index or index == 0 then
        if log then log("Speaker is not in the raid: " .. name) end
        return false, "not in team"
    end
    local passed, result = M.call(team, "MakeTeamOwner", "team" .. index)
    if not passed or result == false then return false, "transfer failed" end
    return true
end

return M
