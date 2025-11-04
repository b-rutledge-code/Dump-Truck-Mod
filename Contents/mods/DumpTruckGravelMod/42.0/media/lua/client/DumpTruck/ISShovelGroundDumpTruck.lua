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

    self:RemoveGapFillers(isoSquare)
end

function ISShovelGround:RemoveEdgeBlend(square)
    if not square then
        return
    end

    -- Check metadata (stored on square, not floor)
    local modData = square:getModData()
    if modData.object == nil then
        print("No object found SHOVEL (" .. square:getX() .. "," .. square:getY() .. ")")
    end
    if modData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND and modData.object then
        DumpTruck.removeOverlayObject(square, modData.object)
        return
    end  
end

function ISShovelGround:RemoveGapFillers(square)
    if not square then
        return
    end

    -- Check adjacent squares (N, E, S, W) and remove gap fillers from them
    -- Leave the passed square alone
    local adjacentSquares = {
        square:getN(), -- North
        square:getE(), -- East
        square:getS(), -- South
        square:getW()  -- West
    }

    for _, adjSquare in ipairs(adjacentSquares) do
        if adjSquare then
            local modData = adjSquare:getModData()
            if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.GAP_FILLER and modData.object then
                DumpTruck.removeOverlayObject(adjSquare, modData.object)
            end
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