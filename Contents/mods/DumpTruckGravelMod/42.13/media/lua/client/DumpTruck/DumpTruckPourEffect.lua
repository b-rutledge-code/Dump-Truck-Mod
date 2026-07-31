local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local DumpTruckPourEffect = {}

local pending = {}

-- Squares whose pour has been scheduled but is not finished, keyed by coordinate.
local pendingUntil = {}

local function keyFor(square)
    return square:getX() .. "," .. square:getY() .. "," .. square:getZ()
end

local function pourDurationMs()
    return DumpTruckConstants.POUR_STAGE_MS * #DumpTruckConstants.POUR_SPRITES
end

--[[
    isPending: true while a pour on this square is still resolving.

    An MP client no longer places the floor itself, so a poured square keeps reading as
    plain terrain until the server's copy arrives. Overlapping rows would otherwise pour it
    a second time and charge the truck twice.
]]
function DumpTruckPourEffect.isPending(square)
    if not square then return false end
    local expiry = pendingUntil[keyFor(square)]
    return expiry ~= nil and getTimestampMs() < expiry
end

function DumpTruckPourEffect.schedulePlaceAndEffect(square, vehicle)
    if not square or not vehicle then return end

    local DumpTruck = require("DumpTruck/DumpTruckGravel")

    pendingUntil[keyFor(square)] = getTimestampMs() + pourDurationMs()

    local sprites = DumpTruckConstants.POUR_SPRITES
    local firstSprite = sprites and sprites[1] and getSprite(sprites[1]) or nil

    -- Save old floor sprite before replacing it
    local oldFloorSprite = nil
    local floor = square:getFloor()
    if floor and floor:getSprite() then
        oldFloorSprite = floor:getSprite():getName()
    end

    --[[
        An MP client leaves the floor to the server, which places it on consumeGravel and
        ships it over as AddItemToMap. Placing one here as well leaves the square carrying
        two stacked gravel floors. getFloor() resolves to whichever comes first, so an edge
        blend attached to it is drawn underneath the server's copy and stays invisible until
        a relog discards the local world and rebuilds the square from the server.
    ]]
    if not isClient() then
        DumpTruck.placeGravelFloorOnSquare(DumpTruckConstants.GRAVEL_SPRITE, square)
    end

    if isServer() then
        DumpTruck.consumeGravelFromTruckBed(vehicle)
    else
        sendClientCommand(getPlayer(), "DumpTruckGravelMod", "consumeGravel", {
            vehicle = vehicle:getId(),
            x = square:getX(),
            y = square:getY(),
            z = square:getZ(),
        })
    end

    if not firstSprite then return end

    -- The fake floor stands in for the terrain the local placement just replaced. With no
    -- local placement the real terrain is still there, so adding one would be the duplicate
    -- this branch exists to avoid.
    local fakeFloor = nil
    if not isClient() then
        if not oldFloorSprite then return end
        local oldSpriteObj = getSprite(oldFloorSprite)
        if not oldSpriteObj then return end
        fakeFloor = IsoObject.new(getCell(), square, oldSpriteObj)
        square:AddTileObject(fakeFloor)
    end

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

function DumpTruckPourEffect.scheduleDelayedReveal(square, oldFloorSpriteName)
    if not square or not oldFloorSpriteName then return end

    local oldSpriteObj = getSprite(oldFloorSpriteName)
    if not oldSpriteObj then return end

    local fakeFloor = IsoObject.new(getCell(), square, oldSpriteObj)
    square:AddTileObject(fakeFloor)
    square:DirtySlice()

    local sprites = DumpTruckConstants.POUR_SPRITES
    local numStages = #sprites
    local totalDelay = DumpTruckConstants.POUR_STAGE_MS * numStages

    local now = getTimestampMs()
    table.insert(pending, {
        fakeFloor = fakeFloor,
        overlay = nil,
        square = square,
        stage = numStages,
        nextSwapAt = now + totalDelay,
    })
end

local function onTick()
    local now = getTimestampMs()

    for key, expiry in pairs(pendingUntil) do
        if now >= expiry then pendingUntil[key] = nil end
    end

    if #pending == 0 then return end

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
                if entry.fakeFloor then
                    sq:RemoveTileObject(entry.fakeFloor)
                end
                if entry.overlay then
                    sq:RemoveTileObject(entry.overlay)
                end
                sq:RecalcProperties()
                sq:DirtySlice()
                table.remove(pending, i)
            end
        end
    end
end

Events.OnTick.Add(onTick)

return DumpTruckPourEffect
