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
    
    -- Fallback: check objects directly in case metadata was lost
    local objects = square:getObjects()
    if objects then
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj and obj:getSprite() then
                local spriteName = obj:getSprite():getName()
                if spriteName and spriteName:find("^" .. DumpTruckConstants.EDGE_BLEND_SPRITES .. "_") then
                    square:RemoveTileObject(obj)
                    square:RecalcProperties()
                    square:DirtySlice()
                    if isClient() then
                        square:transmitFloor()
                    end
                    return
                end
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