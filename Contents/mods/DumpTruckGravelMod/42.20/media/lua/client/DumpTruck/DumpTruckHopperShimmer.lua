-- Cycle hopper interior gravel frames while stock is changing (fill in progress).
-- Shimmer is baked with radial UV falloff so motion reads strongest at the outlet.

local DumpTruckHopper = require("DumpTruck/DumpTruckHopper")

local POLL_SECONDS = 0.5
-- 0.15 * 3/2: one-third slower frame swaps (ripples read clearer).
local FRAME_SECONDS = 0.225
local HOLD_SECONDS = 4.0
local SEARCH_RADIUS = 12

local lastPoll = 0
local lastFrameSwap = 0
local lastStock = nil
local lastAnchorX = nil
local lastAnchorY = nil
local shimmerUntil = 0
local frameIndex = 1

local function now()
    if getTimestampMs ~= nil then
        return getTimestampMs() / 1000.0
    end
    return getGameTime():getWorldAgeHours() * 3600.0
end

local function findGravelObject(square, plane)
    if square == nil then
        return nil
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        local data = obj.getModData ~= nil and obj:getModData() or nil
        if data ~= nil and data.hopperGravelPlane == plane then
            return obj
        end
        local spr = obj:getSprite()
        local name = spr ~= nil and spr:getName() or nil
        if name ~= nil and string.sub(name, 1, 14) == "hopper_gravel_" then
            return obj
        end
    end
    return nil
end

local function applyFrame(anchor, plane, index)
    local entries = DumpTruckHopper.gravelCellsForPlane(plane)
    if entries == nil or anchor == nil then
        return
    end
    local cell = getCell()
    if cell == nil then
        return
    end
    local ax = anchor:getX()
    local ay = anchor:getY()
    local az = anchor:getZ()
    for i = 1, #entries do
        local e = entries[i]
        local frames = e.frames
        if frames ~= nil and #frames >= 1 then
            local spriteName = frames[((index - 1) % #frames) + 1]
            local sprite = spriteName ~= nil and getSprite(spriteName) or nil
            if sprite ~= nil then
                local sq = cell:getGridSquare(ax + e.gx, ay + e.gy, az + (e.fz or 2))
                local obj = findGravelObject(sq, plane)
                if obj ~= nil and obj.setSprite ~= nil then
                    obj:setSprite(sprite)
                end
            end
        end
    end
end

local function onTick()
    if isServer() then
        return
    end
    local t = now()
    local player = getPlayer()
    if player == nil then
        return
    end
    local square = player:getCurrentSquare()
    if square == nil then
        return
    end

    if t - lastPoll >= POLL_SECONDS then
        lastPoll = t
        local anchor = DumpTruckHopper.anchorNear(square, SEARCH_RADIUS)
        if anchor == nil then
            if shimmerUntil > 0 and t >= shimmerUntil and lastAnchorX ~= nil then
                -- Settled with no nearby hopper — nothing to reset.
                shimmerUntil = 0
                frameIndex = 1
                lastStock = nil
                lastAnchorX = nil
                lastAnchorY = nil
            end
            return
        end
        local stock = DumpTruckHopper.getStock(anchor)
        local ax, ay = anchor:getX(), anchor:getY()
        if lastStock ~= nil and (stock ~= lastStock or ax ~= lastAnchorX or ay ~= lastAnchorY) then
            shimmerUntil = t + HOLD_SECONDS
        end
        lastStock = stock
        lastAnchorX = ax
        lastAnchorY = ay
    end

    if shimmerUntil <= 0 then
        return
    end

    local anchor = DumpTruckHopper.anchorNear(square, SEARCH_RADIUS)
    if anchor == nil then
        return
    end
    local plane = DumpTruckHopper.planeForStock(DumpTruckHopper.getStock(anchor))
    if plane == nil then
        shimmerUntil = 0
        frameIndex = 1
        return
    end

    if t >= shimmerUntil then
        applyFrame(anchor, plane, 1)
        shimmerUntil = 0
        frameIndex = 1
        return
    end

    if t - lastFrameSwap >= FRAME_SECONDS then
        lastFrameSwap = t
        frameIndex = frameIndex + 1
        if frameIndex > 3 then
            frameIndex = 1
        end
        applyFrame(anchor, plane, frameIndex)
    end
end

Events.OnTick.Add(onTick)
