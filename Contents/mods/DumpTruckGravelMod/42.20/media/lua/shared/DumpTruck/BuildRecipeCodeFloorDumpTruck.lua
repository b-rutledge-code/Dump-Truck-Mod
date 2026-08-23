-- Build-menu gravel/sand/dirt floors (GravelFloor entity via ISBuildIsoEntity) go through
-- BuildRecipeCode.floor, not ISNaturalFloor. OnCreate never writes pouredFloor /
-- shovelledSprites, and OnIsValid rejects a square that already wears the same floor
-- sprite — which blocks upgrading a gap filler (full road sprite + triangle). Wrap both.

local DumpTruckConstants = require("DumpTruck/DumpTruckConstants")
local DumpTruckCore = require("DumpTruck/DumpTruckCore")
local DumpTruckOverlays = require("DumpTruck/DumpTruckOverlays")

local function textureName(object)
    if not object then
        return nil
    end
    if object.getTextureName then
        local name = object:getTextureName()
        if name then
            return name
        end
    end
    local sprite = object.getSprite and object:getSprite()
    return sprite and sprite.getName and sprite:getName() or nil
end

local function pourableFromCraftRecipe(craftRecipeData)
    if not craftRecipeData or not craftRecipeData.getAllRecordedConsumedItems then
        return nil
    end
    local consumed = craftRecipeData:getAllRecordedConsumedItems()
    if not consumed then
        return nil
    end
    for i = 0, consumed:size() - 1 do
        local item = consumed:get(i)
        local fullType = item and item.getFullType and item:getFullType()
        local pourable = fullType and DumpTruckConstants.POURABLE_BY_BAG[fullType]
        if pourable then
            return pourable
        end
    end
    return nil
end

local function squareHasFarming(square)
    for i = 0, square:getObjects():size() - 1 do
        local object = square:getObjects():get(i)
        if (object:getTextureName() and luautils.stringStarts(object:getTextureName(), "vegetation_farming"))
                or (object:getSpriteName() and luautils.stringStarts(object:getSpriteName(), "vegetation_farming")) then
            return true
        end
    end
    return false
end

local function isGapFillerUpgrade(square, tileSprite)
    if not square or not tileSprite or not DumpTruckConstants.POURABLE_BY_SPRITE[tileSprite] then
        return false
    end
    local overlay = DumpTruckCore.classifySquare(square)
    return overlay ~= nil and overlay.type == DumpTruckConstants.TILE_TYPES.GAP_FILLER
end

local function installBuildRecipeFloorHooks()
    if not BuildRecipeCode or not BuildRecipeCode.floor or BuildRecipeCode.floor.__dumpTruckFloorHooks then
        return
    end

    local originalOnIsValid = BuildRecipeCode.floor.OnIsValid
    function BuildRecipeCode.floor.OnIsValid(params)
        local square = params and params.square
        local tileSprite = params.tileInfo and params.tileInfo:getSpriteName()
        if isGapFillerUpgrade(square, tileSprite) then
            if square:HasStairsBelow() then
                return false
            end
            if squareHasFarming(square) then
                return false
            end
            if not square:connectedWithFloor() then
                return false
            end
            params.testCollisions = false
            return true
        end
        return originalOnIsValid(params)
    end

    local originalOnCreate = BuildRecipeCode.floor.OnCreate
    function BuildRecipeCode.floor.OnCreate(params)
        local thumpable = params and params.thumpable
        local square = thumpable and thumpable:getSquare()
        local shovelledSprites = square and DumpTruckCore.getShovelledSpritesForPour(square) or nil

        if originalOnCreate then
            originalOnCreate(params)
        end

        if not thumpable or not square then
            return
        end

        local pourable = pourableFromCraftRecipe(params.craftRecipeData)
            or DumpTruckConstants.POURABLE_BY_SPRITE[textureName(thumpable)]
        if not pourable then
            return
        end

        local floor = square:getFloor() or thumpable
        local modData = floor:getModData()
        modData.pouredFloor = pourable.floorType
        modData.shovelled = nil
        if shovelledSprites and #shovelledSprites > 0 then
            modData.shovelledSprites = shovelledSprites
        end
        if isServer() then
            floor:transmitModData()
        end

        DumpTruckOverlays.settleAfterPlace(square)
    end

    BuildRecipeCode.floor.__dumpTruckFloorHooks = true
    print("[DumpTruck] BuildRecipeCode.floor OnIsValid/OnCreate hooked")
end

Events.OnGameBoot.Add(installBuildRecipeFloorHooks)
Events.OnInitWorld.Add(installBuildRecipeFloorHooks)
