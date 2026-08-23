-- Chat command to toggle DumpTruckCore.debugMode without editing code.
-- /dtdebug          — toggle
-- /dtdebug on|off   — set explicitly
-- /dumptruckdebug   — same
--
-- SP: flips the shared flag in this process.
-- MP client: flips local flag and asks the server to match, so heal/pour logs appear
-- where the world is owned.

require "Chat/ISChat"

local DumpTruckCore = require("DumpTruck/DumpTruckCore")

local COMMAND_NAMES = {
    ["/dtdebug"] = true,
    ["/dumptruckdebug"] = true,
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function applyDebugMode(enabled)
    DumpTruckCore.debugMode = enabled and true or false
    local state = DumpTruckCore.debugMode and "ON" or "OFF"
    print("[DumpTruck] debugMode " .. state .. " (/dtdebug)")
    if isClient() then
        sendClientCommand(getPlayer(), "DumpTruckGravelMod", "setDebugMode", {
            enabled = DumpTruckCore.debugMode,
        })
    end
end

local originalOnCommandEntered = ISChat.onCommandEntered

function ISChat:onCommandEntered()
    local raw = ISChat.instance and ISChat.instance.textEntry and ISChat.instance.textEntry:getText()
    if raw then
        local text = trim(raw)
        local cmd, rest = text:match("^(%S+)%s*(.*)$")
        if cmd and COMMAND_NAMES[string.lower(cmd)] then
            local arg = string.lower(trim(rest or ""))
            local enabled
            if arg == "on" or arg == "1" or arg == "true" then
                enabled = true
            elseif arg == "off" or arg == "0" or arg == "false" then
                enabled = false
            else
                enabled = not DumpTruckCore.debugMode
            end
            applyDebugMode(enabled)
            self:unfocus()
            self.textEntry:setText("")
            return
        end
    end

    return originalOnCommandEntered(self)
end
