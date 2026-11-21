-- Ground control on the hopper. Fill bed is a timed action, like a gas pump.
-- The hopper holds 600 gravel bags (three full 200-bag truck beds).

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

local DumpTruckHopper = {}

-- Model tile (2, 3): south face of the +X, +Y column. slice world_col → (-3, +3).
DumpTruckHopper.PANEL_DX = -3
DumpTruckHopper.PANEL_DY = 3
DumpTruckHopper.ANCHOR = "loading_hopper_0"
DumpTruckHopper.BAG = "Base.Gravelbag"
DumpTruckHopper.BAG_WEIGHT = 2.0
-- Three full beds. A bed is 400 capacity / 2 weight per bag.
DumpTruckHopper.CAPACITY = 600
-- Action units per bag. A full 200-bag bed is about one gas-tank fill.
DumpTruckHopper.TIME_PER_BAG = 10
-- Looped dump clip played while the hopper fills. Stopped on finish or cancel.
DumpTruckHopper.FILL_SOUND = "GravelDumpLoop"
-- Vehicle origin is often the cab. Bed under the chute can put that a few tiles off bay center.
local BAY_X = 5.0
local BAY_Y = 7.0
local PANEL_REACH = 2.2
local MAX_BAGS = 250

local nextActionId = 0
local fills = {}

function DumpTruckHopper.nextActionId()
    nextActionId = nextActionId + 1
    return nextActionId
end

local function spriteName(obj)
    if obj == nil or obj.getSprite == nil then
        return nil
    end
    local spr = obj:getSprite()
    if spr == nil or spr.getName == nil then
        return nil
    end
    return spr:getName()
end

-- Anchor sprite: the mesh stamp's loading_hopper_0, or the flood stamp's invisible
-- tile (DumpTruck.Hopper2dAnchorSprite, set by shared LoadingHopper2dCells.lua).
local function isAnchorName(name)
    if name == nil then
        return false
    end
    if name == DumpTruckHopper.ANCHOR then
        return true
    end
    return DumpTruck ~= nil and name == DumpTruck.Hopper2dAnchorSprite
end

local function squareHasAnchor(square)
    if square == nil then
        return false
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        if isAnchorName(spriteName(objs:get(i))) then
            return true
        end
    end
    return false
end

local function anchorObject(square)
    if square == nil then
        return nil
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        local obj = objs:get(i)
        if isAnchorName(spriteName(obj)) then
            return obj
        end
    end
    return nil
end

local function transmitAnchor(obj)
    if obj ~= nil and isServer() and obj.transmitModData ~= nil then
        obj:transmitModData()
    end
end

function DumpTruckHopper.getStock(anchorSquare)
    local obj = anchorObject(anchorSquare)
    if obj == nil then
        return 0
    end
    local data = obj:getModData()
    if data.hopperBags == nil then
        return DumpTruckHopper.CAPACITY
    end
    local n = tonumber(data.hopperBags) or 0
    if n < 0 then
        return 0
    end
    return math.floor(n)
end

function DumpTruckHopper.spendStock(anchorSquare, count)
    if count == nil or count < 1 then
        return 0
    end
    local obj = anchorObject(anchorSquare)
    if obj == nil then
        return 0
    end
    local data = obj:getModData()
    local before = data.hopperBags
    if before == nil then
        before = DumpTruckHopper.CAPACITY
    else
        before = math.floor(tonumber(before) or 0)
    end
    if before < 1 then
        data.hopperBags = 0
        transmitAnchor(obj)
        return 0
    end
    local spent = math.min(before, math.floor(count))
    data.hopperBags = before - spent
    transmitAnchor(obj)
    return spent
end

local function squareHasHopperPiece(square)
    if square == nil then
        return false
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        local name = spriteName(objs:get(i))
        if name ~= nil and (string.sub(name, 1, 15) == "loading_hopper_" or string.sub(name, 1, 10) == "hopper_2d_") then
            return true
        end
    end
    return false
end

function DumpTruckHopper.findAnchorNear(square, radius)
    if square == nil then
        return nil
    end
    local cell = getCell()
    if cell == nil then
        return nil
    end
    local r = radius or 8
    local z = square:getZ()
    local best = nil
    local bestD = nil
    for dx = -r, r do
        for dy = -r, r do
            local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, z)
            if squareHasAnchor(sq) then
                local dist = dx * dx + dy * dy
                if best == nil or dist < bestD then
                    best = sq
                    bestD = dist
                end
            end
        end
    end
    return best
end

function DumpTruckHopper.anchorFrom(square)
    if square == nil then
        return nil
    end
    local cell = getCell()
    if cell == nil then
        return nil
    end
    -- Exact reverse of the panel offset.
    local panelAnchor = cell:getGridSquare(
        square:getX() - DumpTruckHopper.PANEL_DX,
        square:getY() - DumpTruckHopper.PANEL_DY,
        square:getZ()
    )
    if squareHasAnchor(panelAnchor) then
        return panelAnchor
    end
    -- Clicked a hopper piece, or grass next to one: find the bay-center anchor nearby.
    if squareHasHopperPiece(square) then
        return DumpTruckHopper.findAnchorNear(square, 6)
    end
    return DumpTruckHopper.findAnchorNear(square, 4)
end

function DumpTruckHopper.panelSquare(anchor)
    if anchor == nil then
        return nil
    end
    local cell = getCell()
    if cell == nil then
        return nil
    end
    return cell:getGridSquare(
        anchor:getX() + DumpTruckHopper.PANEL_DX,
        anchor:getY() + DumpTruckHopper.PANEL_DY,
        anchor:getZ()
    )
end

-- Same rule as a vanilla fuel pump: grid power, or an exterior generator covering the square.
function DumpTruckHopper.hasPower(square)
    if square == nil then
        return false
    end
    if square:hasGridPower() then
        return true
    end
    return SandboxVars.AllowExteriorGenerator == true and square:haveElectricity()
end

function DumpTruckHopper.truckInBay(anchor, vehicle)
    if anchor == nil or vehicle == nil then
        return false
    end
    if vehicle:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then
        return false
    end
    if math.floor(vehicle:getZ()) ~= anchor:getZ() then
        return false
    end
    local dx = vehicle:getX() - (anchor:getX() + 0.5)
    local dy = vehicle:getY() - (anchor:getY() + 0.5)
    return math.abs(dx) <= BAY_X and math.abs(dy) <= BAY_Y
end

local function eachVehicle(fn)
    local cell = getCell()
    if cell == nil or cell.getVehicles == nil then
        return
    end
    local vehicles = cell:getVehicles()
    if vehicles == nil then
        return
    end
    if vehicles.iterator ~= nil then
        local iterator = vehicles:iterator()
        while iterator:hasNext() do
            fn(iterator:next())
        end
        return
    end
    if vehicles.size ~= nil and vehicles.get ~= nil then
        for i = 0, vehicles:size() - 1 do
            fn(vehicles:get(i))
        end
    end
end

function DumpTruckHopper.findTruck(anchor)
    local best = nil
    local bestD = nil
    eachVehicle(function(vehicle)
        if vehicle == nil then
            return
        end
        if not DumpTruckHopper.truckInBay(anchor, vehicle) then
            return
        end
        local dx = vehicle:getX() - (anchor:getX() + 0.5)
        local dy = vehicle:getY() - (anchor:getY() + 0.5)
        local dist = dx * dx + dy * dy
        if best == nil or dist < bestD then
            best = vehicle
            bestD = dist
        end
    end)
    return best
end

local function eachEmptySack(container, fn)
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item ~= nil and item:getFullType() == DumpTruckConstants.EMPTY_BAG_TYPE then
            fn(item)
        end
    end
end

-- Empties count as fill slots (hopper fills them in place). Then new bags for leftover weight room.
function DumpTruckHopper.bagsThatFit(vehicle)
    if vehicle == nil then
        return 0
    end
    local part = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if part == nil then
        return 0
    end
    local container = part:getItemContainer()
    if container == nil then
        return 0
    end
    local capacity = container:getCapacity()
    local weight = container:getContentsWeight()
    local emptyWeight = nil
    local empties = 0
    eachEmptySack(container, function(item)
        empties = empties + 1
        if emptyWeight == nil then
            emptyWeight = item:getWeight()
        end
    end)
    if emptyWeight == nil then
        emptyWeight = 0.3
    end
    local convertible = 0
    local w = weight
    for _ = 1, empties do
        local nextW = w - emptyWeight + DumpTruckHopper.BAG_WEIGHT
        if nextW > capacity then
            break
        end
        w = nextW
        convertible = convertible + 1
    end
    local newBags = 0
    if w + DumpTruckHopper.BAG_WEIGHT <= capacity then
        newBags = math.floor((capacity - w) / DumpTruckHopper.BAG_WEIGHT)
    end
    return convertible + newBags
end

function DumpTruckHopper.bagsForFill(anchor, vehicle)
    local room = DumpTruckHopper.bagsThatFit(vehicle)
    local stock = DumpTruckHopper.getStock(anchor)
    return math.min(room, stock)
end

local function takeEmptySack(container)
    local found = nil
    eachEmptySack(container, function(item)
        if found == nil then
            found = item
        end
    end)
    return found
end

local function nearPanel(player, anchorX, anchorY, anchorZ)
    if player == nil or player:getVehicle() ~= nil then
        return false
    end
    if math.floor(player:getZ()) ~= anchorZ then
        return false
    end
    local px = anchorX + DumpTruckHopper.PANEL_DX + 0.5
    local py = anchorY + DumpTruckHopper.PANEL_DY + 0.5
    return math.abs(player:getX() - px) <= PANEL_REACH and math.abs(player:getY() - py) <= PANEL_REACH
end

-- Add gravel bags until this action has delivered `want` of them.
-- Repeated calls with the same action id are safe. Each bag spent from the hopper
-- is decremented in the same step that adds it to the truck.
function DumpTruckHopper.applyFill(player, vehicle, anchorX, anchorY, anchorZ, actionId, want)
    if isClient() then
        return
    end
    if player == nil or vehicle == nil or actionId == nil then
        return
    end
    want = math.floor(tonumber(want) or 0)
    if want < 1 then
        return
    end
    if want > MAX_BAGS then
        want = MAX_BAGS
    end
    local cell = getCell()
    if cell == nil then
        return
    end
    local anchor = cell:getGridSquare(anchorX, anchorY, anchorZ)
    if not squareHasAnchor(anchor) then
        return
    end
    if not nearPanel(player, anchorX, anchorY, anchorZ) then
        return
    end
    if not DumpTruckHopper.hasPower(DumpTruckHopper.panelSquare(anchor)) then
        return
    end
    if not DumpTruckHopper.truckInBay(anchor, vehicle) then
        return
    end

    local state = fills[vehicle:getId()]
    if state == nil or state.id ~= actionId then
        state = { id = actionId, added = 0 }
        fills[vehicle:getId()] = state
    end

    local part = vehicle:getPartById(DumpTruckConstants.PART_NAME)
    if part == nil then
        return
    end
    local container = part:getItemContainer()
    if container == nil then
        return
    end

    local function refundStock()
        local obj = anchorObject(anchor)
        if obj ~= nil then
            local data = obj:getModData()
            data.hopperBags = (tonumber(data.hopperBags) or 0) + 1
            transmitAnchor(obj)
        end
    end

    while state.added < want do
        if DumpTruckHopper.getStock(anchor) < 1 then
            break
        end
        local capacity = container:getCapacity()
        local weight = container:getContentsWeight()
        local empty = takeEmptySack(container)
        if empty ~= nil then
            local emptyWeight = empty:getWeight()
            if weight - emptyWeight + DumpTruckHopper.BAG_WEIGHT > capacity then
                break
            end
            if DumpTruckHopper.spendStock(anchor, 1) < 1 then
                break
            end
            if isServer() then
                sendRemoveItemFromContainer(container, empty)
            end
            container:Remove(empty)
            local gravel = container:AddItem(DumpTruckHopper.BAG)
            if gravel == nil then
                refundStock()
                break
            end
            if isServer() then
                sendAddItemToContainer(container, gravel)
            end
            container:setDrawDirty(true)
            state.added = state.added + 1
        else
            if weight + DumpTruckHopper.BAG_WEIGHT > capacity then
                break
            end
            if DumpTruckHopper.spendStock(anchor, 1) < 1 then
                break
            end
            local item = container:AddItem(DumpTruckHopper.BAG)
            if item == nil then
                refundStock()
                break
            end
            if isServer() then
                sendAddItemToContainer(container, item)
            end
            container:setDrawDirty(true)
            state.added = state.added + 1
        end
    end
end

function DumpTruckHopper.requestFill(player, vehicle, anchorX, anchorY, anchorZ, actionId, want)
    if vehicle == nil then
        return
    end
    if isClient() then
        sendClientCommand(player, "DumpTruckGravelMod", "hopperFill", {
            vehicle = vehicle:getId(),
            actionId = actionId,
            want = want,
            x = anchorX,
            y = anchorY,
            z = anchorZ,
        })
        return
    end
    DumpTruckHopper.applyFill(player, vehicle, anchorX, anchorY, anchorZ, actionId, want)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "DumpTruckGravelMod" or command ~= "hopperFill" or args == nil then
        return
    end
    if not isServer() then
        return
    end
    local vehicle = getVehicleById(args.vehicle)
    DumpTruckHopper.applyFill(player, vehicle, args.x, args.y, args.z, args.actionId, args.want)
end)

return DumpTruckHopper
