local DumpTruckConstants = require("DumpTruckConstants")

-- Hook into the radial menu without overriding
local originalShowRadialMenu = ISVehicleMenu.showRadialMenu

function ISVehicleMenu.showRadialMenu(playerObj)
    -- Call the original function to populate the default menu
    originalShowRadialMenu(playerObj)

    -- Get the menu instance
    local menu = getPlayerRadialMenu(playerObj:getPlayerNum())

    -- Ensure we're inside a vehicle
    local vehicle = playerObj:getVehicle()
    if vehicle and vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
        local data = vehicle:getModData()
        local isDumping = data.dumpingGravelActive or false

        -- Add your custom slice for gravel dumping
        menu:addSlice(
            isDumping and "Stop Dumping Gravel" or "Start Dumping Gravel",
            getTexture("media/ui/vehicles/dumpbed.png"), -- Replace with a better icon if available
            function()
                data.dumpingGravelActive = not isDumping
                print("Dumping Gravel Active:", data.dumpingGravelActive)
            end
        )
    end
end 