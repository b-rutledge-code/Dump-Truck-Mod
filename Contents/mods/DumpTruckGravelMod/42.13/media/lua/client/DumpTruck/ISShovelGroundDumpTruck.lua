local DumpTruck = require("DumpTruck/DumpTruckGravel")

local originalPerform = ISShovelGround.perform

-- Override perform to cleanup edge blends when shoveling
function ISShovelGround:perform()
    -- Clean up edge blends on the square being shoveled
    if self.sandTile then
        local isoSquare = self.sandTile:getSquare()
        if isoSquare then
            DumpTruck.removeEdgeBlendsBetweenPourableSquares(isoSquare)
        end
    end

    -- Call the original ISShovelGround perform method
    -- Vanilla handles floor removal and attached anims disappear automatically
    if originalPerform then
        originalPerform(self)
    end
end
