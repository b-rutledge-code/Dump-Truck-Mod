-- DumpTruckCardinalLock.lua
-- Automatically locks dump truck heading to cardinal directions for straighter roads
-- Only active when dumping gravel - helps lay perfectly straight roads
-- When driving near a cardinal direction (N/E/S/W) for 3 seconds, locks heading
-- Released by: stopping dump mode, braking, or deliberate steering input

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")

-- No-op when CARDINAL_LOCK constants are not present (e.g. main branch without cardinal feature)
if not DumpTruckConstants.CARDINAL_LOCK then
    return {}
end

local CardinalLock = {}
CardinalLock.debugMode = true  -- Set to false to disable logging
CardinalLock.lastPrintTime = 0

local function debugPrint(...)
    if not CardinalLock.debugMode then return end
    local now = getTimestampMs()
    if now - CardinalLock.lastPrintTime < 500 then return end  -- Throttle to every 500ms
    CardinalLock.lastPrintTime = now
    print("[CardinalLock]", ...)
end

-- Cardinal directions in degrees
local CARDINALS = {0, 90, 180, 270}

-- Normalize angle to -180 to 180 range
local function normalizeAngle(angle)
    while angle > 180 do angle = angle - 360 end
    while angle < -180 do angle = angle + 360 end
    return angle
end

-- Get the nearest cardinal direction if within threshold, nil otherwise
local function getNearestCardinalWithinThreshold(angle, threshold)
    local normalizedAngle = normalizeAngle(angle)
    
    for _, cardinal in ipairs(CARDINALS) do
        local normalizedCardinal = normalizeAngle(cardinal)
        local diff = math.abs(normalizeAngle(normalizedAngle - normalizedCardinal))
        if diff <= threshold then
            return cardinal
        end
    end
    return nil
end

-- Get vehicle modData with cardinal lock state initialized
local function getCardinalLockData(vehicle)
    local data = vehicle:getModData()
    if data.cardinalLock == nil then
        data.cardinalLock = {
            active = false,
            targetHeading = nil,
            nearCardinalTimer = 0,
            nearCardinal = nil,
        }
    end
    return data.cardinalLock
end

-- Main update function - runs every frame for the driver
local function onPlayerUpdate(player)
    if not player then return end
    
    local vehicle = player:getVehicle()
    if not vehicle then return end
    if vehicle:getScriptName() ~= DumpTruckConstants.VEHICLE_SCRIPT_NAME then return end
    if vehicle:getDriver() ~= player then return end
    
    local vehicleData = vehicle:getModData()
    local lockData = getCardinalLockData(vehicle)
    
    -- Only engage cardinal lock when dumping is active
    if not vehicleData.dumpingGravelActive then
        -- Reset lock state when not dumping
        if lockData.active then
            lockData.active = false
            lockData.targetHeading = nil
        end
        lockData.nearCardinalTimer = 0
        lockData.nearCardinal = nil
        return
    end

    local constants = DumpTruckConstants.CARDINAL_LOCK
    
    local currentHeading = vehicle:getAngleZ()
    local currentSteering = vehicle:getCurrentSteering()
    local isBraking = vehicle:isBraking()
    local deltaTime = GameTime:getInstance():getRealworldSecondsSinceLastUpdate()
    
    -- If lock is active, handle correction and release conditions
    if lockData.active then
        -- Release conditions: braking or deliberate steering
        if isBraking or math.abs(currentSteering) > constants.RELEASE_THRESHOLD then
            debugPrint(string.format("RELEASED - braking: %s, steering: %.3f", tostring(isBraking), currentSteering))
            lockData.active = false
            lockData.targetHeading = nil
            lockData.nearCardinalTimer = 0
            lockData.nearCardinal = nil
            return
        end
        
        -- Apply heading correction
        local error = normalizeAngle(lockData.targetHeading - currentHeading)
        local correction = error * constants.CORRECTION_GAIN
        correction = math.max(-1.0, math.min(1.0, correction))
        vehicle:setCurrentSteering(correction)
        local steeringAfter = vehicle:getCurrentSteering()
        debugPrint(string.format("LOCKED target: %.0f | heading: %.1f | error: %.2f | correction: %.3f | applied: %.3f", 
            lockData.targetHeading, currentHeading, error, correction, steeringAfter))
        
    else
        -- Lock not active - check if we should engage
        local nearestCardinal = getNearestCardinalWithinThreshold(currentHeading, constants.DETECTION_THRESHOLD)
        
        if nearestCardinal then
            -- We're near a cardinal direction
            if lockData.nearCardinal == nearestCardinal then
                -- Same cardinal as before, increment timer
                lockData.nearCardinalTimer = lockData.nearCardinalTimer + deltaTime
                debugPrint(string.format("TIMER: %.1f/%.1f sec near %d° (heading: %.1f°)", 
                    lockData.nearCardinalTimer, constants.DELAY, nearestCardinal, currentHeading))
                
                -- Check if we've been near long enough to lock
                if lockData.nearCardinalTimer >= constants.DELAY then
                    -- Only actually lock if we're within the tight lock threshold
                    local tightCardinal = getNearestCardinalWithinThreshold(currentHeading, constants.LOCK_THRESHOLD)
                    if tightCardinal then
                        lockData.active = true
                        lockData.targetHeading = tightCardinal
                        debugPrint(string.format("ENGAGED lock at %d°", tightCardinal))
                    else
                        -- Timer done but not close enough - keep waiting
                        debugPrint(string.format("WAITING - need to be within %d° (currently %.1f° from %d°)", 
                            constants.LOCK_THRESHOLD, math.abs(normalizeAngle(currentHeading - nearestCardinal)), nearestCardinal))
                    end
                end
            else
                -- Different cardinal (or first detection), reset timer
                lockData.nearCardinal = nearestCardinal
                lockData.nearCardinalTimer = deltaTime
                debugPrint(string.format("NEW cardinal detected: %d° (heading: %.1f°)", nearestCardinal, currentHeading))
            end
        else
            -- Not near any cardinal, reset
            if lockData.nearCardinal then
                debugPrint(string.format("LEFT cardinal zone (heading: %.1f°)", currentHeading))
            end
            lockData.nearCardinalTimer = 0
            lockData.nearCardinal = nil
        end
    end
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)

-- Log constants on load to verify they're correct
local c = DumpTruckConstants.CARDINAL_LOCK
if c then
    print(string.format("[CardinalLock] Loaded - DETECT: %d°, LOCK: %d°, DELAY: %ds, RELEASE: %.1f, GAIN: %.2f",
        c.DETECTION_THRESHOLD, c.LOCK_THRESHOLD, c.DELAY, c.RELEASE_THRESHOLD, c.CORRECTION_GAIN))
end

return CardinalLock
