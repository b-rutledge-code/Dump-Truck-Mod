-- Hand-poured gravel/sand/dirt: allow upgrading a gap filler (costs one bag via vanilla
-- consume), and settle edge blends / L-pocket fillers after vanilla lays the floor.
-- create() runs from client ISBuildAction on a cursor copy, so this lives in shared.

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")
local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local function installNaturalFloorHooks()
    if not ISNaturalFloor or ISNaturalFloor.__dumpTruckFloorHooks then
        return
    end

    local originalIsValid = ISNaturalFloor.isValid
    function ISNaturalFloor:isValid(square)
        if square and DumpTruckConstants.POURABLE_BY_FLOOR_TYPE[self.floorType] then
            local overlay = DumpTruckCore.classifySquare(square)
            if overlay and overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER then
                if CFarmingSystem.instance:getLuaObjectOnSquare(square) then
                    return false
                end
                if square:getProperties() and square:getProperties():has(IsoFlagType.water) then
                    return false
                end
                local playerInv = self.character:getInventory()
                if self.item ~= nil and square:getFloor() ~= nil then
                    if playerInv:containsRecursive(self.item) then
                        return true
                    end
                    self.item = playerInv:getFirstTypeRecurse(self.itemType)
                    return self.item ~= nil
                end
                return false
            end
        end
        return originalIsValid(self, square)
    end

    local originalCreate = ISNaturalFloor.create
    function ISNaturalFloor:create(x, y, z, north, sprite)
        originalCreate(self, x, y, z, north, sprite)

        local floorType = self.floorType
        if not floorType and self.item then
            floorType = self:getFloorType(self.item)
        end
        if not DumpTruckConstants.POURABLE_BY_FLOOR_TYPE[floorType] then
            return
        end

        local sq = self.sq
        if not sq and x and y and z ~= nil then
            local cell = getCell()
            sq = cell and cell:getGridSquare(x, y, z) or nil
        end
        if not sq then
            return
        end

        DumpTruckOverlays.settleAfterPlace(sq)
    end

    ISNaturalFloor.__dumpTruckFloorHooks = true
    print("[DumpTruck] ISNaturalFloor isValid/create hooked")
end

Events.OnGameBoot.Add(installNaturalFloorHooks)
Events.OnInitWorld.Add(installNaturalFloorHooks)
