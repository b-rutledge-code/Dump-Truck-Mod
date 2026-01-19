local DumpTruck = require("DumpTruck/DumpTruckGravel")

local originalBuildIsoEntityCreate = ISBuildIsoEntity.create

-- Override ISBuildIsoEntity:create to clean up edge blends after placing gravel from build menu
function ISBuildIsoEntity:create(x, y, z, north, sprite)
    -- Call the original ISBuildIsoEntity create method first
    if originalBuildIsoEntityCreate then
        originalBuildIsoEntityCreate(self, x, y, z, north, sprite)
    end

    -- After the tile is placed, clean up any edge blends between adjacent gravel tiles
    if self.sq and DumpTruck.isFullGravelFloor(self.sq) then
        DumpTruck.removeEdgeBlendsBetweenPourableSquares(self.sq)
    end
end

