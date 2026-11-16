-- Stand at the hopper control and fill the truck bed. Same shape as fueling from a pump.

require "TimedActions/ISBaseTimedAction"

local DumpTruckHopper = require("DumpTruck/DumpTruckHopper")

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
    action.character:stopOrTriggerSound(action.sound)
    action.sound = nil
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
    local square = self.character:getCurrentSquare()
    if square == nil or square:getZ() ~= self.anchorZ then
        return false
    end
    local dx = math.abs(square:getX() - (self.anchorX + DumpTruckHopper.PANEL_DX))
    local dy = math.abs(square:getY() - (self.anchorY + DumpTruckHopper.PANEL_DY))
    return dx <= 1 and dy <= 1
end

function ISFillHopper:waitToStart()
    self.character:faceLocation(self.anchorX + DumpTruckHopper.PANEL_DX, self.anchorY + DumpTruckHopper.PANEL_DY)
    return self.character:shouldBeTurning()
end

function ISFillHopper:update()
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
        self.sound = self.character:playSound(DumpTruckHopper.FILL_SOUND)
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
    -- Stand on the south side of the panel (bay end) so the truck stays in view.
    local cell = getCell()
    local stand = cell:getGridSquare(panel:getX(), panel:getY() + 1, panel:getZ())
    if stand == nil or not luautils.walkAdj(playerObj, stand) then
        if not luautils.walkAdj(playerObj, panel) then
            return
        end
    end
    ISTimedActionQueue.add(ISFillHopper:new(
        playerObj,
        vehicle,
        anchor:getX(),
        anchor:getY(),
        anchor:getZ(),
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
