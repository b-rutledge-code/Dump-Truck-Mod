local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruck = require("DumpTruck/DumpTruckGravel")

local originalPerform = ISExitVehicle.perform

--[[
    Override perform to end the dump session when the driver climbs out, so a truck left
    mid-dump is quiet and disarmed.

    The vehicle is read before the original runs: vanilla calls vehicle:exit() and only then
    triggers OnExitVehicle, passing the character alone, so by the time that event fires
    character:getVehicle() is nil.
]]
function ISExitVehicle:perform()
    local vehicle = self.character and self.character:getVehicle()
    -- A driverless truck covers the driver who switched to a passenger seat before getting out.
    -- A passenger leaving while someone still drives is skipped: stopDumping writes synced
    -- modData, so that client would disarm a session it does not own.
    local shouldEndDump = vehicle
            and (vehicle:getDriver() == self.character or vehicle:getDriver() == nil)

    if originalPerform then
        originalPerform(self)
    end

    if shouldEndDump and vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
        DumpTruck.stopDumping(vehicle)
    end
end
