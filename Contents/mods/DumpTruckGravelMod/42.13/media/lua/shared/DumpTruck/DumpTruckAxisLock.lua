local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")

local DumpTruckAxisLock = {}

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

function DumpTruckAxisLock.getNearestHeading(vehicle)
    if not vehicle then return "?" end
    local rawFx, rawFy = DumpTruckCore.getVectorFromPlayer(vehicle)
    if not rawFx or not rawFy then return "?" end
    local fx, fy = snapVectorToCardinal(rawFx, rawFy)
    return headingLabel(fx, fy)
end

function DumpTruckAxisLock.engage(vehicle)
    if not vehicle then return false end

    local angleZ = normalizeAngle(vehicle:getAngleZ())

    -- Check if close enough to a cardinal heading (0, 90, 180, 270)
    local minDiff = 999
    for _, center in ipairs({0, 90, 180, 270}) do
        local d = angleDiff(angleZ, center)
        if d < minDiff then minDiff = d end
    end
    if minDiff > DumpTruckConstants.AXIS_LOCK_ENGAGE_THRESHOLD then
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

    local data = vehicle:getModData()
    data.axisLockActive = true
    data.axisLockAxis = lockAxis
    data.axisLockValue = lockedValue
    data.axisLockHeading = headingLabel(fx, fy)
    data.axisLockFx = fx
    data.axisLockFy = fy

    return true
end

function DumpTruckAxisLock.disengage(vehicle)
    if not vehicle then return end
    local data = vehicle:getModData()
    data.axisLockActive = nil
    data.axisLockAxis = nil
    data.axisLockValue = nil
    data.axisLockHeading = nil
    data.axisLockFx = nil
    data.axisLockFy = nil
end

function DumpTruckAxisLock.isActive(vehicle)
    if not vehicle then return false end
    return vehicle:getModData().axisLockActive == true
end

function DumpTruckAxisLock.getSnappedPosition(vehicle, cx, cy)
    if not vehicle then return cx, cy end
    local data = vehicle:getModData()
    if not data.axisLockActive then return cx, cy end

    if data.axisLockAxis == "X" then
        return data.axisLockValue, cy
    else
        return cx, data.axisLockValue
    end
end

function DumpTruckAxisLock.getLockedForwardVector(vehicle)
    if not vehicle then return nil, nil end
    local data = vehicle:getModData()
    if not data.axisLockActive then return nil, nil end
    if not data.axisLockFx or not data.axisLockFy then return nil, nil end
    return data.axisLockFx, data.axisLockFy
end

function DumpTruckAxisLock.checkDrift(vehicle, cx, cy)
    if not vehicle then return false end
    local data = vehicle:getModData()
    if not data.axisLockActive then return false end

    local drift
    if data.axisLockAxis == "X" then
        drift = math.abs(cx - data.axisLockValue)
    else
        drift = math.abs(cy - data.axisLockValue)
    end

    return drift > DumpTruckConstants.AXIS_LOCK_DRIFT_MAX
end

return DumpTruckAxisLock
