local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local DumpTruckPourEffect = {}

local pending = {}

function DumpTruckPourEffect.schedulePlaceAndEffect(square, vehicle)
    if not square or not vehicle then return end

    local DumpTruck = require("DumpTruck/DumpTruckGravel")

    local sprites = DumpTruckConstants.POUR_SPRITES
    local firstSprite = sprites and sprites[1] and getSprite(sprites[1]) or nil

    -- Save old floor sprite before replacing it
    local oldFloorSprite = nil
    local floor = square:getFloor()
    if floor and floor:getSprite() then
        oldFloorSprite = floor:getSprite():getName()
    end

    DumpTruck.placeGravelFloorOnSquare(DumpTruckConstants.GRAVEL_SPRITE, square)
    DumpTruck.consumeGravelFromTruckBed(vehicle)

    if not firstSprite or not oldFloorSprite then return end

    local oldSpriteObj = getSprite(oldFloorSprite)
    if not oldSpriteObj then return end

    local fakeFloor = IsoObject.new(getCell(), square, oldSpriteObj)
    square:AddTileObject(fakeFloor)

    local overlay = IsoObject.new(getCell(), square, firstSprite)
    square:AddTileObject(overlay)

    local now = getTimestampMs()
    table.insert(pending, {
        fakeFloor = fakeFloor,
        overlay = overlay,
        square = square,
        stage = 1,
        nextSwapAt = now + DumpTruckConstants.POUR_STAGE_MS,
    })
end

local function onTick()
    if #pending == 0 then return end

    local now = getTimestampMs()
    local sprites = DumpTruckConstants.POUR_SPRITES
    local numStages = #sprites

    for i = #pending, 1, -1 do
        local entry = pending[i]
        if now >= entry.nextSwapAt then
            if entry.stage < numStages then
                local nextSprite = getSprite(sprites[entry.stage + 1])
                if nextSprite then
                    entry.overlay:setSprite(nextSprite)
                    entry.overlay:DirtySlice()
                end
                entry.stage = entry.stage + 1
                entry.nextSwapAt = now + DumpTruckConstants.POUR_STAGE_MS
            else
                local sq = entry.square
                sq:RemoveTileObject(entry.fakeFloor)
                sq:RemoveTileObject(entry.overlay)
                sq:RecalcProperties()
                sq:DirtySlice()
                table.remove(pending, i)
            end
        end
    end
end

Events.OnTick.Add(onTick)

return DumpTruckPourEffect
