-- DumpTruckSound.lua
-- Zoom × Vehicle Engine Volume gain for dump file clips.

local DumpTruckSound = {}

DumpTruckSound.NEAR_GAIN = 1.0
DumpTruckSound.FAR_GAIN = 0.35

function DumpTruckSound.getGain(nearGain, farGain)
    nearGain = nearGain or DumpTruckSound.NEAR_GAIN
    farGain = farGain or DumpTruckSound.FAR_GAIN

    local zoomFactor = nearGain
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
        zoomFactor = nearGain + (farGain - nearGain) * t
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
