local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")
local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")
local DumpTruckSnapLine = require("DumpTruck/DumpTruckSnapLine")

local DumpTruck = {}

-- GRAVEL

function DumpTruck.placeGravelFloorOnSquare(sprite, sq)
    if not sprite or not sq then
        return
    end
    
    -- If upgrading a gap filler, remove the attached triangle overlay first
    local existingFloor = sq:getFloor()
    local floorModData = existingFloor and existingFloor:getModData()
    if floorModData and floorModData.overlayType == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
        existingFloor:RemoveAttachedAnims()
        -- NOTE: Intentionally NOT calling resetOverlayMetadata or transmitUpdatedSpriteToClients here
        -- The floor is about to be replaced by addFloor() below, which wipes everything anyway
    end
    
    -- Save original floor sprite so it can be restored when shoveled
    local originalFloor = sq:getFloor()
    local shovelledSprites = nil
    if originalFloor and originalFloor:getSprite() then
        shovelledSprites = {}
        -- Save the main sprite only
        table.insert(shovelledSprites, originalFloor:getSprite():getName())
    end
    
    local newFloor = sq:addFloor(sprite)
    -- Set modData on the new floor so it can be restored when shoveled
    if newFloor and shovelledSprites and #shovelledSprites > 0 then
        local floorModData = newFloor:getModData()
        floorModData.shovelledSprites = shovelledSprites
        floorModData.pouredFloor = DumpTruckConstants.POURED_FLOOR_TYPE
        floorModData.shovelled = nil  -- Clear shovelled flag (matches vanilla behavior)
        newFloor:transmitModData()  -- Sync to other clients
    end
    if newFloor then
        DumpTruckCore.debugPrint("[DumpTruck] tile (", sq:getX(), ", ", sq:getY(), ", ", sq:getZ(), ")")
    end

    -- Disable erosion on this square
    sq:disableErosion()
    -- Tell clients to set doNothing on their copy (erosion state does not sync with floor change)
    if isServer() then
        sendServerCommand("DumpTruckGravelMod", "disableErosionAt", { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
    end

    DumpTruckOverlays.removeOppositeEdgeBlends(sq)

    
    sq:RecalcProperties()
    sq:DirtySlice()
    if sq.transmitFloor then sq:transmitFloor() end
end

-- Send current row to server so it can run smoothRoad (edge blends sync to all clients).
-- Caller already ran smoothRoad locally, so in SP we must NOT run it again (would run twice and second run replaces/clears blends).
local function sendSmoothRoadToServer(currentSquares)
    if not currentSquares or #currentSquares < 2 then return end
    if not isClient() then
        -- SP: smoothRoad was already run by caller (tryPourGravelUnderTruck). Do not run again.
        return
    end
    local squareList = {}
    for _, sq in ipairs(currentSquares) do
        if sq then
            table.insert(squareList, { x = sq:getX(), y = sq:getY(), z = sq:getZ() })
        end
    end
    if #squareList >= 2 then
        sendClientCommand(getPlayer(), "DumpTruckGravelMod", "smoothRoad", { squares = squareList })
    end
end

function DumpTruck.consumeGravelFromTruckBed(vehicle)
    if DumpTruckCore.debugMode then
        return true
    end

    local truckBed = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if not truckBed or not truckBed:getItemContainer() then
        return false
    end

    local container = truckBed:getItemContainer()
    local items = container:getItems()

    for i = 0, items:size() - 1 do
        local item = items:get(i)

        if item:getFullType() == DumpTruckConstants.BAG_TYPE then
            local currentUses = item:getCurrentUses()
            if currentUses > 0 then
                local newCount = currentUses - 1
                item:setCurrentUses(newCount)
                if newCount <= 0 then
                    -- Remove empty sack and add EmptySandbag; sync so clients see bed change
                    if isServer() then
                        sendRemoveItemFromContainer(container, item)
                    end
                    container:Remove(item)
                    local newItem = container:AddItem("Base.EmptySandbag")
                    if isServer() and newItem then
                        sendAddItemToContainer(container, newItem)
                    end
                else
                    -- Same item, fewer uses; sync so clients see the count change
                    if isServer() then
                        sendReplaceItemInContainer(container, item, item)
                    end
                end
                container:setDrawDirty(true)
                return true
            end
        end
    end

    return false
end

function DumpTruck.getGravelCount(vehicle)
    if DumpTruckCore.debugMode then
        return 100
    end

    local totalUses = 0
    local truckBed = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if not truckBed or not truckBed:getItemContainer() then
        return totalUses
    end
    local items = truckBed:getItemContainer():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == DumpTruckConstants.BAG_TYPE then
            local currentUses = item:getCurrentUses()
            totalUses = totalUses + currentUses
        end
    end
    return totalUses
end

-- ROAD BUILDING


--[[
    getBackSquares: Gets the squares behind the truck for gravel placement
    Input:
        fx: number - Forward vector X component
        fy: number - Forward vector Y component
        cx: number - Current X position
        cy: number - Current Y position
        cz: number - Z level (usually 0)
        width: number - Width of gravel road in tiles
        length: number - Length of truck in tiles
    Output: array of IsoGridSquare - The squares where gravel should be placed
]]
function DumpTruck.getBackSquares(fx, fy, cx, cy, cz, width, length)
    
    -- Calculate offset backwards along forward vector
    local offsetDistance = (length/2)  -- Half truck length plus 1 tile
    local offsetX = -fx * offsetDistance  -- Negative forward vector
    local offsetY = -fy * offsetDistance
    
    -- Apply offset to center point
    local centerX = cx + math.floor(offsetX + 0.5)  -- Round to nearest integer
    local centerY = cy + math.floor(offsetY + 0.5)
    
    -- Calculate perpendicular vector (90 degrees) for road width
    -- For a vector (x,y) in Zomboid's inverted Y coordinate system
    -- We use (-y,x) because Y is inverted, so this gives us a vector to the right of the truck
    local perpX = -fy   -- In inverted Y, this gives us right
    local perpY = fx
    
    -- Find the dominant axis and snap to it
    -- This ensures we get a clean cardinal direction
    if math.abs(perpX) > math.abs(perpY) then
        -- Snap to East/West
        perpX = perpX > 0 and 1 or -1
        perpY = 0
    else
        -- Snap to North/South
        perpX = 0
        perpY = perpY > 0 and 1 or -1
    end
    
    -- Generate points based on width
    local points = {}
    for i = 0, width - 1 do
        table.insert(points, {
            x = centerX + (perpX * i),
            y = centerY + (perpY * i),
            z = cz
        })
    end
    
    -- Convert points to squares
    local squares = {}
    for _, point in ipairs(points) do
        local square = getCell():getGridSquare(point.x, point.y, point.z)
        if square then
            table.insert(squares, square)
        end
    end
    
    return squares
end

--[[
    getLinePoints: Bresenham line from (x0,y0) to (x1,y1) inclusive.
    Returns list of {x=int, y=int} for tile-gap interpolation.
]]
function DumpTruck.getLinePoints(x0, y0, x1, y1)
    local points = {}
    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx - dy
    local x, y = x0, y0
    while true do
        table.insert(points, { x = x, y = y })
        if x == x1 and y == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            x = x + sx
        end
        if e2 < dx then
            err = err + dx
            y = y + sy
        end
    end
    return points
end

-- Modify tryPourGravelUnderTruck to handle transitions (per-vehicle last tile + gap interpolation)
function DumpTruck.tryPourGravelUnderTruck(vehicle)
    if not vehicle or vehicle:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then return end

    local data = vehicle:getModData()
    if not data.dumpingGravelActive then return end  -- Only proceed if dumping is active

    local cx, cy, cz = vehicle:getX(), vehicle:getY(), vehicle:getZ()
    cz = 0 -- Assume ground level for simplicity

    -- Axis lock: brake and drift checks before anything else
    if DumpTruckSnapLine.isActive(vehicle) then
        if vehicle:isBraking() or DumpTruckSnapLine.checkDrift(vehicle, cx, cy) then
            DumpTruck.stopDumping(vehicle)
            DumpTruckSnapLine.disengage(vehicle)
            vehicle:playSound("VehicleReverseBuzzer")
            return
        end
    end

    -- Get forward vector (axis lock overrides driver direction)
    local fx, fy
    if DumpTruckSnapLine.isActive(vehicle) then
        fx, fy = DumpTruckSnapLine.getLockedForwardVector(vehicle)
    end
    if not fx or not fy then
        fx, fy = DumpTruckCore.getVectorFromPlayer(vehicle)
    end
    if not fx or not fy then
        return
    end

    -- Calculate perpendicular vector (90 degrees to forward)
    local perpX = -fy
    local perpY = fx
    
    -- Apply threshold only in perpendicular direction (sideways drift)
    local threshold = 0.3
    local adjustedX = cx + (perpX * threshold)
    local adjustedY = cy + (perpY * threshold)
    local tileX = math.floor(adjustedX)
    local tileY = math.floor(adjustedY)
    DumpTruckCore.debugPrint("[DumpTruck] vehicle tile (", tileX, ", ", tileY, ", ", cz, ")")
    
    -- Road dimensions (needed for both single-tile and interpolation paths)
    local script = vehicle:getScript()
    local extents = script:getExtents()
    local vehicleWidth = math.floor(extents:x() + 0.5)
    local length = math.floor(extents:z() + 0.5)
    local roadWidth = vehicleWidth
    if (data.wideRoadMode or false) and vehicleWidth < 3 then
        roadWidth = vehicleWidth + 1
    end

    if DumpTruck.getGravelCount(vehicle) <= 0 then
        DumpTruck.stopDumping(vehicle)
        return
    end

    local DumpTruckPourEffect = require("DumpTruck/DumpTruckPourEffect")

    -- First run: no previous tile — single-tile path only (avoid placing from 0,0 to current)
    if data.dumpLastTileX == nil then
        local snapCx, snapCy = DumpTruckSnapLine.getSnappedPosition(vehicle, cx, cy)
        local currentSquares = DumpTruck.getBackSquares(fx, fy, snapCx, snapCy, cz, roadWidth, length)
        for _, sq in ipairs(currentSquares) do
            if sq and DumpTruckCore.isSquareValidForGravel(sq) then
                DumpTruckPourEffect.schedulePlaceAndEffect(sq, vehicle)
                if DumpTruck.getGravelCount(vehicle) <= 0 then
                    DumpTruck.stopDumping(vehicle)
                    return
                end
            end
        end
        DumpTruckOverlays.smoothRoad(currentSquares, fx, fy)
        sendSmoothRoadToServer(currentSquares)
        data.dumpLastTileX = tileX
        data.dumpLastTileY = tileY
        return
    end

    if tileX == data.dumpLastTileX and tileY == data.dumpLastTileY then return end

    -- Gap: step > 1 — Bresenham walk, skip first point, place at each (full road width per position)
    if math.abs(tileX - data.dumpLastTileX) > 1 or math.abs(tileY - data.dumpLastTileY) > 1 then
        local points = DumpTruck.getLinePoints(data.dumpLastTileX, data.dumpLastTileY, tileX, tileY)
        for i = 2, #points do
            local ix, iy = points[i].x, points[i].y
            local icx, icy = ix + 0.5, iy + 0.5
            if DumpTruckSnapLine.isActive(vehicle) then
                icx, icy = DumpTruckSnapLine.getSnappedPosition(vehicle, icx, icy)
            end
            local squares = DumpTruck.getBackSquares(fx, fy, icx, icy, cz, roadWidth, length)
            for _, sq in ipairs(squares) do
                if sq and DumpTruckCore.isSquareValidForGravel(sq) then
                    DumpTruckPourEffect.schedulePlaceAndEffect(sq, vehicle)
                    if DumpTruck.getGravelCount(vehicle) <= 0 then
                        DumpTruck.stopDumping(vehicle)
                        data.dumpLastTileX = tileX
                        data.dumpLastTileY = tileY
                        DumpTruckOverlays.smoothRoad(squares, fx, fy)
                        sendSmoothRoadToServer(squares)
                        return
                    end
                end
            end
            -- Edge blends for this row (smoothRoad uses first/last of list only)
            DumpTruckOverlays.smoothRoad(squares, fx, fy)
            sendSmoothRoadToServer(squares)
        end
        data.dumpLastTileX = tileX
        data.dumpLastTileY = tileY
        return
    end

    -- Single-tile step: place at current position only
    cx, cy = DumpTruckSnapLine.getSnappedPosition(vehicle, cx, cy)
    local currentSquares = DumpTruck.getBackSquares(fx, fy, cx, cy, cz, roadWidth, length)
    for _, sq in ipairs(currentSquares) do
        if sq and DumpTruckCore.isSquareValidForGravel(sq) then
            DumpTruckPourEffect.schedulePlaceAndEffect(sq, vehicle)
            if DumpTruck.getGravelCount(vehicle) <= 0 then
                DumpTruck.stopDumping(vehicle)
                data.dumpLastTileX = tileX
                data.dumpLastTileY = tileY
                DumpTruckOverlays.smoothRoad(currentSquares, fx, fy)
                sendSmoothRoadToServer(currentSquares)
                return
            end
        end
    end
    DumpTruckOverlays.smoothRoad(currentSquares, fx, fy)
    sendSmoothRoadToServer(currentSquares)
    data.dumpLastTileX = tileX
    data.dumpLastTileY = tileY
end

-- Update function for player actions
local elapsedTime = 0
function DumpTruck.onPlayerUpdateFunc(player)
    if player then
        local vehicle = player:getVehicle()
        if vehicle and vehicle:getScriptName() == DumpTruckConstants.VEHICLE_SCRIPT_NAME then
            local deltaTime = GameTime:getInstance():getRealworldSecondsSinceLastUpdate()
            elapsedTime = elapsedTime + deltaTime  -- Safe addition
            if elapsedTime < DumpTruckConstants.UPDATE_INTERVAL then
                return
            end
            elapsedTime = 0

            -- Run only where the driver runs (MP client or SP). Dedicated server must not run this (requires client module).
            if isServer() then
                -- Dedicated server: skip (no client module)
            else
                DumpTruck.tryPourGravelUnderTruck(vehicle)
            end
        end
    end
end
Events.OnPlayerUpdate.Add(DumpTruck.onPlayerUpdateFunc)

-- Stop dumping sounds
function DumpTruck.stopDumpingSounds(vehicle, soundID)
    
    -- Stop loop if playing
    if soundID and soundID ~= 0 then
        local emitter = vehicle:getEmitter()
        if emitter then
            emitter:stopSound(soundID)
        end
    end
    
    -- Only play stop sounds if we have a valid soundID (meaning dumping was actually active)
    if soundID and soundID ~= 0 then
        vehicle:playSound("HydraulicLiftDown")
        vehicle:playSound("GravelDumpEnd")
    end
    
    -- Clear from modData
    local data = vehicle:getModData()
    data.gravelLoopSoundID = nil
end

-- Start dumping
function DumpTruck.startDumping(vehicle)
    local data = vehicle:getModData()
    data.dumpingGravelActive = true
    data.dumpLastTileX = nil
    data.dumpLastTileY = nil

    -- Start dumping sounds
    vehicle:playSound("HydraulicLiftRaised")
    vehicle:playSound("GravelDumpStart")
    local emitter = vehicle:getEmitter()
    data.gravelLoopSoundID = emitter:playSound("GravelDumpLoop")
end

-- Stop dumping
function DumpTruck.stopDumping(vehicle)
    local data = vehicle:getModData()
    
    -- Only stop if actually dumping (prevents repeated calls)
    if not data.dumpingGravelActive then
        return
    end
    
    data.dumpingGravelActive = false
    data.dumpLastTileX = nil
    data.dumpLastTileY = nil

    -- Stop dumping sounds
    DumpTruck.stopDumpingSounds(vehicle, data.gravelLoopSoundID)
end


-- Recreate overlay sprites from floor modData when squares load (handles persistence)
-- Uses AttachExistingAnim to reattach sprite to floor
-- MP: when server places gravel it sends disableErosionAt; clients run disableErosion() on their copy so erosion (trees/grass) does not run there
-- Client receives commands FROM server (e.g. disableErosionAt after server places gravel)
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "DumpTruckGravelMod" or not args then return end
    if command == "disableErosionAt" and args.x and args.y and args.z then
        local cell = getCell()
        if cell then
            local sq = cell:getGridSquare(args.x, args.y, args.z)
            if sq then sq:disableErosion() end
        end
    end
end)

-- Server receives commands FROM client (place gravel + consume, and smoothRoad for edge blends)
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "DumpTruckGravelMod" or not args then return end
    if command == "consumeGravel" and args.vehicle then
        local vehicle = getVehicleById(args.vehicle)
        if not vehicle then
            return
        end
        if vehicle:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then return end
        -- Only place gravel on dedicated server; in SP client already placed (blends would be wiped by a second place)
        if isServer() and args.x and args.y and args.z then
            local cell = getCell()
            if cell then
                local sq = cell:getGridSquare(args.x, args.y, args.z)
                if sq then
                    DumpTruck.placeGravelFloorOnSquare(DumpTruckConstants.GRAVEL_SPRITE, sq)
                end
            end
        end
        DumpTruck.consumeGravelFromTruckBed(vehicle)
    elseif command == "smoothRoad" and args.squares and #args.squares >= 2 then
        local cell = getCell()
        if not cell then
            return
        end
        local serverSquares = {}
        for _, pt in ipairs(args.squares) do
            if pt.x and pt.y and pt.z then
                local sq = cell:getGridSquare(pt.x, pt.y, pt.z)
                if sq then table.insert(serverSquares, sq) end
            end
        end
        if #serverSquares >= 2 then
            DumpTruckOverlays.smoothRoad(serverSquares, 0, 0)
        end
    elseif command == "clearOverlayAt" and args.x and args.y and args.z then
        local cell = getCell()
        if cell then
            local sq = cell:getGridSquare(args.x, args.y, args.z)
            if sq then
                DumpTruckOverlays.removeOverlayFromSquare(sq)
            end
        end
    end
end)

Events.LoadGridsquare.Add(function(square)
    local floor = square:getFloor()
    if not floor then return end

    local floorModData = floor:getModData()
    if floorModData and floorModData.overlaySprite then
        if not floor:hasAttachedAnimSprites() then
            local sprite = getSprite(floorModData.overlaySprite)
            if sprite then
                floor:AttachExistingAnim(sprite, 0, 0, false, 0, false, 0.0)
            end
        end
    end
end)


return DumpTruck