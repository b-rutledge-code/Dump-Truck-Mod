local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruck = require("DumpTruck/DumpTruckGravel")
local DumpTruckAxisLock = require("DumpTruck/DumpTruckAxisLock")

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
        local dumpIcon = isDumping and "media/ui/vehicles/not_dumping.png" or "media/ui/vehicles/dumping.png"
        
        menu:addSlice(
            isDumping and "Stop Dumping Gravel" or "Start Dumping Gravel",
            getTexture(dumpIcon),
            function()
                if isDumping then
                    DumpTruck.stopDumping(vehicle)
                else
                    DumpTruck.startDumping(vehicle)
                end
            end
        )
        
        -- Add road width toggle (only for vehicles < 3 tiles wide)
        local script = vehicle:getScript()
        local extents = script:getExtents()
        local vehicleWidth = math.floor(extents:x() + 0.5)
        
        if vehicleWidth < 3 then
            local wideMode = data.wideRoadMode or false
            local nextWidth = wideMode and vehicleWidth or (vehicleWidth + 1)
            local roadIcon = "media/ui/vehicles/road_" .. nextWidth .. ".png"
            
            menu:addSlice(
                "Road Width: " .. nextWidth .. " tiles",
                getTexture(roadIcon),
                function()
                    data.wideRoadMode = not wideMode
                end
            )
        end

        local isLocked = DumpTruckAxisLock.isActive(vehicle)
        local lockLabel
        if isLocked then
            lockLabel = "Disable Axis Lock (" .. (data.axisLockHeading or "?") .. ")"
        else
            local nearestHeading = DumpTruckAxisLock.getNearestHeading(vehicle)
            lockLabel = "Enable Axis Lock (" .. nearestHeading .. ")"
        end
        local lockIcon = isLocked and "media/ui/vehicles/axis_lock_off.png" or "media/ui/vehicles/axis_lock_on.png"

        menu:addSlice(
            lockLabel,
            getTexture(lockIcon),
            function()
                if isLocked then
                    DumpTruckAxisLock.disengage(vehicle)
                    vehicle:playSound("VehicleDoorCloseWindow")
                else
                    local ok = DumpTruckAxisLock.engage(vehicle)
                    if ok then
                        vehicle:playSound("VehicleSeatBelt")
                    else
                        vehicle:playSound("VehicleReverseBuzzer")
                    end
                end
            end
        )
    end
end 