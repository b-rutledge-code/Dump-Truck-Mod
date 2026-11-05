--[[
    DumpTruckGravelMod - World loot

    Adds vanilla CrateGravelBags to construction and McCoy logging rooms.
    OnPreDistributionMerge runs before ItemPickerJava.Parse().
]]

local GRAVEL_CRATE = "CrateGravelBags"

local function addCrate(roomName, containerName, entry)
    local rooms = Distributions[1]
    if not rooms then
        return
    end

    local room = rooms[roomName]
    if not room then
        return
    end

    local container = room[containerName]
    if not container or not container.procList then
        return
    end

    local procList = container.procList
    for i = 1, #procList do
        local existing = procList[i]
        if existing and existing.name == entry.name then
            return
        end
    end

    table.insert(procList, entry)
end

local function addGravelBagCrates()
    addCrate("construction", "other", {
        name = GRAVEL_CRATE,
        min = 0,
        max = 4,
        weightChance = 115,
    })
    addCrate("loggingfactory", "crate", {
        name = GRAVEL_CRATE,
        min = 0,
        max = 4,
        weightChance = 40,
    })
    addCrate("loggingwarehouse", "crate", {
        name = GRAVEL_CRATE,
        min = 0,
        max = 4,
        weightChance = 40,
    })
end

Events.OnPreDistributionMerge.Add(addGravelBagCrates)
