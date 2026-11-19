-- Stand at the hopper control and fill the truck bed. Same shape as fueling from a pump.

require "TimedActions/ISBaseTimedAction"

local DumpTruckHopper = require("DumpTruck/DumpTruckHopper")
local DumpTruckSound = require("DumpTruck/DumpTruckSound")

ISFillHopper = ISBaseTimedAction:derive("ISFillHopper")

local function vehicleOf(action)
    if action.vehicle ~= nil then
        return action.vehicle
    end
    return getVehicleById(action.vehicleId)
end

local function stopFillSound(action)
    if action.sound == nil then
        return
    end
    action.soundEmitter:stopOrTriggerSound(action.sound)
    action.sound = nil
    action.soundEmitter = nil
end

-- Control box is on the west face of the panel column (left side of the pole in iso).
-- Facing the tile center from the south aims north at the pole's back/side, not the box.
local function facePanelBox(character, anchorX, anchorY)
    character:faceLocationF(
        anchorX + DumpTruckHopper.PANEL_DX + 0.05,
        anchorY + DumpTruckHopper.PANEL_DY + 0.5
    )
end

-- Same reach as DumpTruckHopper nearPanel. Panel square is solid, so walkAdj's
-- canReachTo(panel) fails even when you're already next to the box and it
-- pathfinds you around to the outside.
local PANEL_REACH = 2.2

local function withinPanelReach(playerObj, anchorX, anchorY, anchorZ)
    if playerObj == nil or math.floor(playerObj:getZ()) ~= anchorZ then
        return false
    end
    local px = anchorX + DumpTruckHopper.PANEL_DX + 0.5
    local py = anchorY + DumpTruckHopper.PANEL_DY + 0.5
    return math.abs(playerObj:getX() - px) <= PANEL_REACH
        and math.abs(playerObj:getY() - py) <= PANEL_REACH
end

function ISFillHopper:isValid()
    if self.character:getVehicle() ~= nil then
        return false
    end
    local cell = getCell()
    if cell == nil then
        return false
    end
    local anchor = cell:getGridSquare(self.anchorX, self.anchorY, self.anchorZ)
    if anchor == nil or not DumpTruckHopper.truckInBay(anchor, vehicleOf(self)) then
        return false
    end
    if DumpTruckHopper.getStock(anchor) < 1 then
        return false
    end
    return withinPanelReach(self.character, self.anchorX, self.anchorY, self.anchorZ)
end

function ISFillHopper:waitToStart()
    facePanelBox(self.character, self.anchorX, self.anchorY)
    return self.character:shouldBeTurning()
end

function ISFillHopper:update()
    facePanelBox(self.character, self.anchorX, self.anchorY)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    local want = math.floor((self.totalBags or 0) * self:getJobDelta() + 0.0001)
    if want > self.sent then
        self.sent = want
        DumpTruckHopper.requestFill(
            self.character, vehicleOf(self), self.anchorX, self.anchorY, self.anchorZ, self.actionId, want
        )
    end
end

function ISFillHopper:start()
    self:setActionAnim("fill_container_tap")
    self:setOverrideHandModels(nil, nil)
    self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
    if DumpTruckHopper.FILL_SOUND ~= nil then
        self.soundEmitter = vehicleOf(self):getEmitter()
        self.sound = DumpTruckSound.play(self.soundEmitter, DumpTruckHopper.FILL_SOUND)
    end
end

function ISFillHopper:stop()
    stopFillSound(self)
    if not isClient() then
        local want = math.floor((self.totalBags or 0) * self:getJobDelta() + 0.0001)
        DumpTruckHopper.applyFill(
            self.character, vehicleOf(self), self.anchorX, self.anchorY, self.anchorZ, self.actionId, want
        )
    end
    ISBaseTimedAction.stop(self)
end

function ISFillHopper:serverStop()
    if self.netAction == nil or self.netAction.getProgress == nil then
        return
    end
    local want = math.floor((self.totalBags or 0) * self.netAction:getProgress() + 0.0001)
    DumpTruckHopper.applyFill(
        self.character, vehicleOf(self), self.anchorX, self.anchorY, self.anchorZ, self.actionId, want
    )
end

function ISFillHopper:perform()
    stopFillSound(self)
    ISBaseTimedAction.perform(self)
end

function ISFillHopper:complete()
    local progress = 1
    if self.netAction ~= nil and self.netAction.getProgress ~= nil then
        progress = self.netAction:getProgress()
    end
    local want = math.floor((self.totalBags or 0) * progress + 0.0001)
    DumpTruckHopper.requestFill(
        self.character, vehicleOf(self), self.anchorX, self.anchorY, self.anchorZ, self.actionId, want
    )
end

function ISFillHopper:getDuration()
    return (self.totalBags or 0) * DumpTruckHopper.TIME_PER_BAG
end

function ISFillHopper:new(character, vehicle, anchorX, anchorY, anchorZ, totalBags, actionId)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.vehicleId = vehicle:getId()
    o.anchorX = anchorX
    o.anchorY = anchorY
    o.anchorZ = anchorZ
    o.totalBags = totalBags
    o.actionId = actionId
    o.sent = 0
    o.sound = nil
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

local function onFill(playerObj, vehicle, anchor, totalBags)
    local panel = DumpTruckHopper.panelSquare(anchor)
    if panel == nil then
        return
    end
    local ax, ay, az = anchor:getX(), anchor:getY(), anchor:getZ()
    -- Stay put when already in reach. walkAdj targets the solid panel tile, fails
    -- canReachTo, and drags you to the outside free tile every time.
    if withinPanelReach(playerObj, ax, ay, az) then
        ISTimedActionQueue.clear(playerObj)
    elseif not luautils.walkAdj(playerObj, panel) then
        return
    end
    ISTimedActionQueue.add(ISFillHopper:new(
        playerObj,
        vehicle,
        ax,
        ay,
        az,
        totalBags,
        DumpTruckHopper.nextActionId()
    ))
end

local function squareFromWorldObjects(worldobjects)
    if worldobjects == nil then
        return nil
    end
    for _, obj in ipairs(worldobjects) do
        if obj ~= nil and obj.getSquare ~= nil then
            local square = obj:getSquare()
            if square ~= nil then
                return square
            end
        end
    end
    return nil
end

local function fillMenu(playerNum, context, worldobjects, test)
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then
        return true
    end
    local playerObj = getSpecificPlayer(playerNum)
    if playerObj == nil or playerObj:getVehicle() ~= nil then
        return
    end
    local square = squareFromWorldObjects(worldobjects)
    if square == nil then
        square = playerObj:getCurrentSquare()
    end
    local anchor = DumpTruckHopper.anchorFrom(square)
    if anchor == nil then
        return
    end
    -- Only offer when the click or the player is next to this hopper.
    local panel = DumpTruckHopper.panelSquare(anchor)
    local nearClick = square ~= nil and (
        math.abs(square:getX() - anchor:getX()) <= 6
        and math.abs(square:getY() - anchor:getY()) <= 6
    )
    local playerSq = playerObj:getCurrentSquare()
    local nearPlayer = playerSq ~= nil and (
        math.abs(playerSq:getX() - anchor:getX()) <= 8
        and math.abs(playerSq:getY() - anchor:getY()) <= 8
    )
    if not nearClick and not nearPlayer then
        return
    end
    if panel == nil then
        return
    end
    local vehicle = DumpTruckHopper.findTruck(anchor)
    if vehicle == nil then
        return
    end
    local stock = DumpTruckHopper.getStock(anchor)
    local room = DumpTruckHopper.bagsThatFit(vehicle)
    local bags = math.min(stock, room)
    if test then
        return true
    end
    if bags < 1 then
        local reason = "bed full"
        if stock < 1 then
            reason = "hopper empty"
        end
        local opt = context:addOption("Fill bed (" .. reason .. ")", nil, nil)
        opt.notAvailable = true
        return
    end
    context:addOption("Fill bed", playerObj, onFill, vehicle, anchor, bags)
end

Events.OnFillWorldObjectContextMenu.Add(fillMenu)
