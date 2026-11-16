-- DumpTruckSound.lua
-- Zoom × Vehicle Engine Volume gain for dump file clips.
-- Zoom factor matches event:/Vehicle/Van/Engine CameraZoom level:
-- 1 - 0.421*t + 0.111*t*t (1.0 zoomed in, 0.69 zoomed out).

local DumpTruckSound = {}

function DumpTruckSound.getGain()
    local zoomFactor = 1
    local player = getPlayer()
    if player then
        local core = getCore()
        local minZoom = core:getMinZoom()
        local maxZoom = core:getMaxZoom()
        local zoom = core:getZoom(player:getPlayerNum())
        local range = maxZoom - minZoom
        local t = 0
        if range > 0 then
            t = (zoom - minZoom) / range
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
        end
        zoomFactor = 1 - 0.421 * t + 0.111 * t * t
    end

    return zoomFactor * (getCore():getOptionVehicleEngineVolume() / 10)
end

function DumpTruckSound.applyGain(emitter, handle)
    if not emitter or not handle or handle == 0 then
        return
    end
    emitter:setVolume(handle, DumpTruckSound.getGain())
end

function DumpTruckSound.play(emitter, name)
    if not emitter then
        return nil
    end
    local handle = emitter:playSound(name)
    DumpTruckSound.applyGain(emitter, handle)
    return handle
end

return DumpTruckSound
