local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")

local DumpTruckSnapLine = {}

DumpTruckSnapLine.active = false
DumpTruckSnapLine.axis = nil
DumpTruckSnapLine.value = nil
DumpTruckSnapLine.heading = nil
DumpTruckSnapLine.fx = nil
DumpTruckSnapLine.fy = nil

local function clearSavedSnapLine(vehicle)
    if not vehicle then return end
    local data = vehicle:getModData()
    data.snapLineActive = nil
    data.snapLineAxis = nil
    data.snapLineValue = nil
    data.snapLineHeading = nil
    data.snapLineFx = nil
    data.snapLineFy = nil
end

local function normalizeAngle(a)
    a = a % 360
    if a < 0 then a = a + 360 end
    return a
end

local function angleDiff(a, b)
    local d = normalizeAngle(a - b)
    if d > 180 then d = 360 - d end
    return d
end

local function snapVectorToCardinal(fx, fy)
    if math.abs(fx) > math.abs(fy) then
        return (fx > 0 and 1 or -1), 0
    else
        return 0, (fy > 0 and 1 or -1)
    end
end

local function headingLabel(fx, fy)
    if fy < 0 then return "N"
    elseif fy > 0 then return "S"
    elseif fx > 0 then return "E"
    else return "W" end
end

function DumpTruckSnapLine.getNearestHeading(vehicle)
    if not vehicle then return "?" end
    local rawFx, rawFy = DumpTruckCore.getVectorFromPlayer(vehicle)
    if not rawFx or not rawFy then return "?" end
    local fx, fy = snapVectorToCardinal(rawFx, rawFy)
    return headingLabel(fx, fy)
end

function DumpTruckSnapLine.engage(vehicle)
    if not vehicle then return false end

    local angleZ = normalizeAngle(vehicle:getAngleZ())

    -- Check if close enough to a cardinal heading (0, 90, 180, 270)
    local minDiff = 999
    for _, center in ipairs({0, 90, 180, 270}) do
        local d = angleDiff(angleZ, center)
        if d < minDiff then minDiff = d end
    end
    if minDiff > DumpTruckConstants.SNAP_LINE_ENGAGE_THRESHOLD then
        return false
    end

    -- Capture the actual forward vector from the driver and snap to cardinal
    local rawFx, rawFy = DumpTruckCore.getVectorFromPlayer(vehicle)
    if not rawFx or not rawFy then return false end

    local fx, fy = snapVectorToCardinal(rawFx, rawFy)

    -- Determine which axis to lock based on the snapped forward direction
    local cx, cy = vehicle:getX(), vehicle:getY()
    local lockAxis, lockedValue
    if fx == 0 then
        lockAxis = "X"
        lockedValue = math.floor(cx + 0.5)
    else
        lockAxis = "Y"
        lockedValue = math.floor(cy + 0.5)
    end

    DumpTruckSnapLine.active = true
    DumpTruckSnapLine.axis = lockAxis
    DumpTruckSnapLine.value = lockedValue
    DumpTruckSnapLine.heading = headingLabel(fx, fy)
    DumpTruckSnapLine.fx = fx
    DumpTruckSnapLine.fy = fy
    clearSavedSnapLine(vehicle)

    return true
end

function DumpTruckSnapLine.disengage(vehicle)
    DumpTruckSnapLine.active = false
    DumpTruckSnapLine.axis = nil
    DumpTruckSnapLine.value = nil
    DumpTruckSnapLine.heading = nil
    DumpTruckSnapLine.fx = nil
    DumpTruckSnapLine.fy = nil
    clearSavedSnapLine(vehicle)
end

function DumpTruckSnapLine.isActive(vehicle)
    if not vehicle then return false end
    return DumpTruckSnapLine.active == true
end

function DumpTruckSnapLine.getSnappedPosition(vehicle, cx, cy)
    if not vehicle or not DumpTruckSnapLine.active then return cx, cy end

    if DumpTruckSnapLine.axis == "X" then
        return DumpTruckSnapLine.value, cy
    else
        return cx, DumpTruckSnapLine.value
    end
end

function DumpTruckSnapLine.getLockedForwardVector(vehicle)
    if not vehicle or not DumpTruckSnapLine.active then return nil, nil end
    if not DumpTruckSnapLine.fx or not DumpTruckSnapLine.fy then return nil, nil end
    return DumpTruckSnapLine.fx, DumpTruckSnapLine.fy
end

function DumpTruckSnapLine.checkDrift(vehicle, cx, cy)
    if not vehicle or not DumpTruckSnapLine.active then return false end

    local drift
    if DumpTruckSnapLine.axis == "X" then
        drift = math.abs(cx - DumpTruckSnapLine.value)
    else
        drift = math.abs(cy - DumpTruckSnapLine.value)
    end

    return drift > DumpTruckConstants.SNAP_LINE_DRIFT_MAX
end

return DumpTruckSnapLine
