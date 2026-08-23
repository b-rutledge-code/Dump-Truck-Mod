local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local originalComplete = ISShovelGround.complete

--[[
    Shovelling a road square leaves an edge the road has never had before. Vanilla restores
    the ground under the shovel and clears that square's own attached sprites, and stops
    there. The heal picks up from its neighbours outward: fillers whose L was dug away, a
    pocket the dig has just opened, and the road faces now looking at open terrain.

    The hook is on `complete`, not `perform`, because `complete` is where vanilla restores
    the ground: the engine runs `perform()` first and `complete()` after it
    (IsoGameCharacter.update), so a heal hung off `perform` would read the square as road and
    do its surgery on a floor vanilla is about to replace.

    `complete` is also the half of the action the engine runs only where the world is owned
    (`if (!GameClient.client)`), which for a multiplayer client's dig is the server. So the
    heal lands beside the restore on the same machine, with no command to route and no race
    to guard against.
]]
function ISShovelGround:complete()
    local isoSquare = self.sandTile and self.sandTile:getSquare()

    local restored = originalComplete(self)

    if restored and isoSquare then
        DumpTruckOverlays.healAfterShovel(isoSquare)
    end

    return restored
end
