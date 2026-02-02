local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local originalPerform = ISShovelGround.perform

-- Override perform to cleanup metadata and adjacent edge blends when shoveling
-- Note: Vanilla's ISShovelGround.perform already calls RemoveAttachedAnims() on the floor
function ISShovelGround:perform()
    if self.sandTile then
        local isoSquare = self.sandTile:getSquare()
        if isoSquare then
            -- Clear our overlay metadata (vanilla handles the anim removal)
            DumpTruckOverlays.resetOverlayMetadata(isoSquare)
            
            -- Remove edge blends on adjacent squares that point to this one
            DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(isoSquare)
        end
    end

    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end
end
