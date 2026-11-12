local api = require("api")
local trace = require("AAC-TnT-RaidTools/core/trace")

-- api.On keeps one callback per event, so this module owns UPDATE and hands every frame to each
-- registered listener, in the order they were added. A listener that raises is skipped (and logged
-- once per distinct message) instead of stopping the others.
local Ticker = {}

local listeners = {}
local logged = {}

-- fn(dt): dt is the milliseconds since the last frame.
function Ticker.Add(fn)
    listeners[#listeners + 1] = fn
end

function Ticker.Start()
    api.On("UPDATE", function(dt)
        for _, fn in ipairs(listeners) do
            local ok, err = pcall(fn, dt)
            if not ok then
                local message = tostring(err)
                if not logged[message] then
                    logged[message] = true
                    trace.Add("[ticker] update listener failed: " .. message)
                end
            end
        end
    end)
end

function Ticker.Stop()
    api.On("UPDATE", function() return end)
    listeners = {}
    logged = {}
end

return Ticker
