-- Protected calls into the game API. Some calls are missing in this game build or fail for
-- out-of-range units, so they run under pcall and give back nil instead of raising.
local Guard = {}

-- safe(label, fn): fn's value, or nil when it raised. Says nothing about failures.
function Guard.Silent(_, fn)
    local ok, value = pcall(fn)
    if ok then return value end
    return nil
end

return Guard
