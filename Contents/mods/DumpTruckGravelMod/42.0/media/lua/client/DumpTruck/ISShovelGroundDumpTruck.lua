local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local originalPerform = ISShovelGround.perform

-- Add functions as methods of ISShovelGround
function ISShovelGround:HandleTileChange(square)
    if not square then 
        return 
    end
    
    -- Get the IsoGridSquare first
    local isoSquare = square:getSquare()
    if not isoSquare then
        return
    end

    self:RemoveEdgeBlend(isoSquare)
    
    -- Remove edge blends between pourable squares
    DumpTruck.removeEdgeBlendsBetweenPourableSquares(isoSquare)
end

function ISShovelGround:RemoveEdgeBlend(square)
    if not square then
        return
    end

    -- First check metadata (fast path if available)
    local floor = square:getFloor()
    if floor then
        local modData = floor:getModData()
        if modData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND and modData.object then
            DumpTruck.removeOverlayObject(square, modData.object)
            return
        end
    end  
end 


function ISShovelGround:perform()
    if self.sandTile then
        self:HandleTileChange(self.sandTile)
    end

    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end
end