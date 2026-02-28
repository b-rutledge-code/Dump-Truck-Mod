local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")

local DumpTruckSnapLine = {}

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

    local data = vehicle:getModData()
    data.snapLineActive = true
    data.snapLineAxis = lockAxis
    data.snapLineValue = lockedValue
    data.snapLineHeading = headingLabel(fx, fy)
    data.snapLineFx = fx
    data.snapLineFy = fy

    return true
end

function DumpTruckSnapLine.disengage(vehicle)
    if not vehicle then return end
    local data = vehicle:getModData()
    data.snapLineActive = nil
    data.snapLineAxis = nil
    data.snapLineValue = nil
    data.snapLineHeading = nil
    data.snapLineFx = nil
    data.snapLineFy = nil
end

function DumpTruckSnapLine.isActive(vehicle)
    if not vehicle then return false end
    return vehicle:getModData().snapLineActive == true
end

function DumpTruckSnapLine.getSnappedPosition(vehicle, cx, cy)
    if not vehicle then return cx, cy end
    local data = vehicle:getModData()
    if not data.snapLineActive then return cx, cy end

    if data.snapLineAxis == "X" then
        return data.snapLineValue, cy
    else
        return cx, data.snapLineValue
    end
end

function DumpTruckSnapLine.getLockedForwardVector(vehicle)
    if not vehicle then return nil, nil end
    local data = vehicle:getModData()
    if not data.snapLineActive then return nil, nil end
    if not data.snapLineFx or not data.snapLineFy then return nil, nil end
    return data.snapLineFx, data.snapLineFy
end

function DumpTruckSnapLine.checkDrift(vehicle, cx, cy)
    if not vehicle then return false end
    local data = vehicle:getModData()
    if not data.snapLineActive then return false end

    local drift
    if data.snapLineAxis == "X" then
        drift = math.abs(cx - data.snapLineValue)
    else
        drift = math.abs(cy - data.snapLineValue)
    end

    return drift > DumpTruckConstants.SNAP_LINE_DRIFT_MAX
end

return DumpTruckSnapLine
