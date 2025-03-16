local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local originalPerform = ISShovelGround.perform

-- Helper function stays global since it's a utility
function isEdgeBlendTile(spriteName)
    -- Check if it's a blends_natural tile
    if not spriteName or type(spriteName) ~= "string" or not spriteName:find("^blends_natural_01_") then
        return false
    end
    
    -- Extract the sprite number
    local spriteNumber = tonumber(spriteName:match("blends_natural_01_(%d+)"))
    if not spriteNumber then return false end
    
    -- Get the relative offset within the row (0-15)
    local relativeOffset = spriteNumber % 16
    
    -- Check if it's a primary edge (8-11) or variation edge (12-15)
    return relativeOffset >= 8 and relativeOffset <= 15
end

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
    
    -- Get adjacent tiles using square methods
    local adjacentSquares = {
        isoSquare:getE(), -- East
        isoSquare:getW(), -- West
        isoSquare:getS(), -- South
        isoSquare:getN()  -- North
    }

    -- Check each adjacent square for blend tiles and remove them
    for _, adjSquare in ipairs(adjacentSquares) do
        if adjSquare then
            self:RemoveBlendTile(adjSquare)
        end
    end
end

function ISShovelGround:RemoveBlendTile(square)
    if not square then
        return
    end

    local floor = square:getFloor()
    if floor and floor:getModData().gravelOverlay then
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local obj = objects:get(i)
            if obj:getSprite() then
                local spriteName = obj:getSprite():getName()

                -- Check if the sprite matches one of the blend tile sprites
                for _, spriteToRemove in pairs(DumpTruckConstants.GRAVEL_BLEND_TILES) do
                    if spriteName == spriteToRemove then
                        square:RemoveTileObject(obj)
                        break
                    end
                end
            end
        end
    end
end 

function ISShovelGround:removeEdgeBlends(isoObject)
    if not isoObject then return end
    
    local square = isoObject:getSquare()
    if not square then return end
    
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        if obj:getSprite() then
            local spriteName = obj:getSprite():getName()
            if isEdgeBlendTile(spriteName) then
                square:RemoveTileObject(obj)
            end
        end
    end
end

function ISShovelGround:perform()
    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end

    if self.sandTile then
        self:HandleTileChange(self.sandTile)
        self:removeEdgeBlends(self.sandTile)
    end
end