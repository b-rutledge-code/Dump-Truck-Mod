local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
require("DumpTruck/DumpTruckGravel") -- Ensure DumpTruck global is loaded

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

    -- Remove edge blend overlay from the square being changed
    self:RemoveEdgeBlend(isoSquare)
    
    -- Remove edge blends between pourable squares (e.g., between two gravel tiles)
    DumpTruck.removeEdgeBlendsBetweenPourableSquares(isoSquare)

    -- Remove gap filler overlays from adjacent squares (N, E, S, W)
    self:RemoveGapFillers(isoSquare)
end

-- Remove edge blend overlay from a square if it exists
-- Uses metadata to find the overlay object by sprite name
function ISShovelGround:RemoveEdgeBlend(square)
    if not square then
        return
    end

    -- Check metadata (stored on square, not floor)
    local modData = square:getModData()
    if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.EDGE_BLEND and modData.sprite then
        local edgeBlendObject = DumpTruck.findOverlayObject(square, modData.sprite)
        if edgeBlendObject then
            DumpTruck.removeOverlayObject(square, edgeBlendObject)
        end
    end  
end

-- Remove gap filler overlays from adjacent squares (N, E, S, W)
-- Called when a tile is changed to clean up gap fillers that are no longer valid
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
            
            if modData and modData.tileType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
                if modData.sprite then
                    local gapFillerObject = DumpTruck.findOverlayObject(adjSquare, modData.sprite)
                    if gapFillerObject then
                        DumpTruck.removeOverlayObject(adjSquare, gapFillerObject)
                    end
                end
            end
        end
    end
end 


-- Override perform to handle cleanup before the original game logic runs
-- This ensures overlays are removed before the tile is changed
function ISShovelGround:perform()


    if self.sandTile then
        self:HandleTileChange(self.sandTile)
    end

    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end

end