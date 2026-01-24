local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruck = require("DumpTruck/DumpTruckGravel")

local originalPerform = ISShovelGround.perform

-- Override perform to cleanup edge blends and gap fillers when shoveling
function ISShovelGround:perform()
    -- Clean up edge blends and gap fillers on the square being shoveled
    if self.sandTile then
        local isoSquare = self.sandTile:getSquare()
        if isoSquare then
            -- Remove gap filler overlay if present
            local squareModData = isoSquare:getModData()
            if squareModData and squareModData.tileType == DumpTruckConstants.TILE_TYPES.GAP_FILLER and squareModData.sprite then
                local overlayObj = DumpTruck.findOverlayObject(isoSquare, squareModData.sprite)
                if overlayObj then
                    isoSquare:RemoveTileObject(overlayObj)
                    DumpTruck.resetOverlayMetadata(isoSquare)
                end
            end
            
            -- Remove edge blends
            DumpTruck.removeEdgeBlendsBetweenPourableSquares(isoSquare)
        end
    end

    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end
end
