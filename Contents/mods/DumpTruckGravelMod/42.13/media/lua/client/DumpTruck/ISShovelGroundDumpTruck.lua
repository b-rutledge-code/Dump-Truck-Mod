local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local originalPerform = ISShovelGround.perform

-- Override perform to clean up adjacent edge blends when shoveling
-- Vanilla's ISShovelGround:complete() clears the shovelled square's own attached anims,
-- on the server too in MP, so there is nothing of ours left to clear there
function ISShovelGround:perform()
    if self.sandTile then
        local isoSquare = self.sandTile:getSquare()
        if isoSquare then
            --[[
                The cleanup reaches onto neighbouring squares, so an MP client has to hand it
                to the server. Run locally and the neighbours keep their blends on the server's
                copy, which puts them back on the next chunk reload. Same reasoning as
                applySmoothRoad: whoever owns the world does the work and syncs the result.
            ]]
            if isClient() then
                sendClientCommand(getPlayer(), "DumpTruckGravelMod", "cleanupBlendsAt", {
                    x = isoSquare:getX(),
                    y = isoSquare:getY(),
                    z = isoSquare:getZ(),
                })
            else
                DumpTruckOverlays.removeEdgeBlendsBetweenPourableSquares(isoSquare)
            end
        end
    end

    -- Call the original ISShovelGround perform method
    if originalPerform then
        originalPerform(self)
    end
end
