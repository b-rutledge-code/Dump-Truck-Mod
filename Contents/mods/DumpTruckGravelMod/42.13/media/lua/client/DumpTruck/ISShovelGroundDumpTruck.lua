local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local originalPerform = ISShovelGround.perform

-- Override perform to cleanup edge blends and gap fillers when shoveling
function ISShovelGround:perform()
    -- Clean up edge blends and gap fillers on the square being shoveled
    if self.sandTile then
        local isoSquare = self.sandTile:getSquare()
        if isoSquare then
            -- Remove overlay (gap filler or edge blend) from this square
            DumpTruckOverlays.removeOverlayFromSquare(isoSquare)
            
            -- Remove edge blends on adjacent squares that point to this one
            DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(isoSquare)
        end
    end

    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end
end
