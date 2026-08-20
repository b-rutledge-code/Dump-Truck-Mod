local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruck = require("DumpTruck/DumpTruckGravel")
local DumpTruckSnapLine = require("DumpTruck/DumpTruckSnapLine")

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
        local isDumping = DumpTruck.dumpingActive

        -- Add your custom slice for gravel dumping
        local dumpIcon = isDumping and "media/ui/vehicles/not_dumping.png" or "media/ui/vehicles/dumping.png"
        
        -- Label and action both follow this client's dump switch at menu open. The click
        -- looks up the live truck (vanilla ignition slices do the same).
        menu:addSlice(
            isDumping and "Stop Dumping Gravel" or "Start Dumping Gravel",
            getTexture(dumpIcon),
            function()
                local live = playerObj:getVehicle()
                if not live or live:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then
                    return
                end
                if isDumping then
                    DumpTruck.stopDumping(live)
                else
                    DumpTruck.startDumping(live)
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
                    local live = playerObj:getVehicle()
                    if not live or live:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then
                        return
                    end
                    local liveData = live:getModData()
                    liveData.wideRoadMode = not (liveData.wideRoadMode or false)
                end
            )
        end

        local isLocked = DumpTruckSnapLine.isActive(vehicle)
        local lockLabel
        if isLocked then
            lockLabel = "Disable Snap Line (" .. (DumpTruckSnapLine.heading or "?") .. ")"
        else
            local nearestHeading = DumpTruckSnapLine.getNearestHeading(vehicle)
            lockLabel = "Enable Snap Line (" .. nearestHeading .. ")"
        end
        local lockIcon = isLocked and "media/ui/vehicles/snap_line_off.png" or "media/ui/vehicles/snap_line_on.png"

        menu:addSlice(
            lockLabel,
            getTexture(lockIcon),
            function()
                local live = playerObj:getVehicle()
                if not live or live:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then
                    return
                end
                if DumpTruckSnapLine.isActive(live) then
                    DumpTruckSnapLine.disengage(live)
                    live:playSound("VehicleDoorCloseWindow")
                else
                    local ok = DumpTruckSnapLine.engage(live)
                    if ok then
                        live:playSound("VehicleSeatBelt")
                    else
                        live:playSound("VehicleReverseBuzzer")
                    end
                end
            end
        )
    end
end 