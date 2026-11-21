-- Preset loading hoppers on the vanilla map. Each site is placed once per save when the
-- player walks within TRIGGER_RADIUS. Single-player only until multiplayer placement is designed.
--
-- Site layout (relative to hopper anchor): gravel 4x12 under the hopper, junction overlay
-- removals on the road edge north of the drive, side blends down both edges of the drive.
-- See docs/design-notes.md (Preset tower site).

DumpTruck = DumpTruck or {}

DumpTruck.PresetTowerSites = {
    { x = 11605, y = 10009 },
}

local MODDATA_KEY = "DumpTruckPresetTowers"
local TRIGGER_RADIUS = 60

local function siteKey(site)
    return tostring(site.x) .. "_" .. tostring(site.y)
end

local function isNear(site, px, py)
    local dx = site.x - px
    local dy = site.y - py
    return dx * dx + dy * dy <= TRIGGER_RADIUS * TRIGGER_RADIUS
end

local function placeNearbySites()
    if isMultiplayer() then
        return
    end
    if DumpTruck.placePresetSite == nil then
        return
    end
    local player = getPlayer()
    if player == nil then
        return
    end
    local px = player:getX()
    local py = player:getY()
    local data = ModData.getOrCreate(MODDATA_KEY)
    data.flooded = data.flooded or {}
    for _, site in ipairs(DumpTruck.PresetTowerSites) do
        local key = siteKey(site)
        if data.flooded[key] ~= true and isNear(site, px, py) then
            local result = DumpTruck.placePresetSite(site.x, site.y)
            if result ~= nil and result.ok == true then
                data.flooded[key] = true
                print(string.format(
                    "[DumpTruck] preset site %s placed (mowed=%d gravel=%d junction=%d side=%d)",
                    key, result.mowed or 0, result.gravelPlaced, result.junctionRemoved, result.sidePlaced
                ))
            else
                local detail = "nil"
                if result ~= nil then
                    detail = string.format(
                        "gravelFail=%s junctionMissing=%s sideFail=%s",
                        tostring(result.gravelFailed), tostring(result.junctionMissing), tostring(result.sideFailed)
                    )
                end
                print(string.format("[DumpTruck] preset site %s place failed (%s)", key, detail))
            end
        end
    end
end

-- EveryOneMinute can stall in some loads; also check on a short real-time tick.
local tickAccum = 0
local function onTick()
    tickAccum = tickAccum + 1
    if tickAccum < 300 then
        return
    end
    tickAccum = 0
    placeNearbySites()
end

Events.EveryOneMinute.Add(placeNearbySites)
Events.OnTick.Add(onTick)
