-- Protected calls into the game API. Some calls are missing in this game build or fail for
-- out-of-range units, so they run under pcall and give back nil instead of raising.
local Guard = {}

-- safe(label, fn): fn's value, or nil when it raised. Says nothing about failures.
function Guard.Silent(_, fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

-- Same, but logs each distinct failure once through log(text).
function Guard.New(log)
    local logged = {}
    return function(label, fn)
        local ok, value = pcall(fn)
        if ok then return value end
        local message = label .. " failed: " .. tostring(value)
        if not logged[message] then
            logged[message] = true
            log(message)
        end
        return nil
    end
end

return Guard
