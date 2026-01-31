local DumpTruckCore = require("DumpTruck/DumpTruckCore")
local DumpTruckGravel = require("DumpTruck/DumpTruckGravel")

local originalBuildIsoEntityCreate = ISBuildIsoEntity.create

-- Override ISBuildIsoEntity:create to clean up edge blends after placing gravel from build menu
function ISBuildIsoEntity:create(x, y, z, north, sprite)
    -- Call the original ISBuildIsoEntity create method first
    if originalBuildIsoEntityCreate then
        originalBuildIsoEntityCreate(self, x, y, z, north, sprite)
    end

    -- After the tile is placed, clean up any edge blends between adjacent gravel tiles
    if self.sq and DumpTruckCore.isFullGravelFloor(self.sq) then
        DumpTruckGravel.removeEdgeBlendsBetweenPourableSquares(self.sq)
    end
end

