local api = require("api")

-- api.On keeps one callback per event, so this module owns UPDATE and hands every frame to each
-- registered listener, in the order they were added. A listener that raises is skipped instead of
-- stopping the others.
local Ticker = {}

local listeners = {}

-- fn(dt): dt is the milliseconds since the last frame.
function Ticker.Add(fn)
    listeners[#listeners + 1] = fn
end

function Ticker.Start()
    api.On("UPDATE", function(dt)
        for _, fn in ipairs(listeners) do
            pcall(fn, dt)
        end
    end)
end

function Ticker.Stop()
    api.On("UPDATE", function() return end)
    listeners = {}
end

return Ticker
