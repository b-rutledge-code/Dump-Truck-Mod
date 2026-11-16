-- Placing the anchor tile stamps the rest of the hopper.
-- Each entry is dx, dy, dz from the anchor square, then the sprite.

local ANCHOR = "loading_hopper_0"
local PIECES = {
    {4, -4, 0, "loading_hopper_1"},
    {3, -4, 0, "loading_hopper_2"},
    {2, -4, 0, "loading_hopper_3"},
    {1, -4, 0, "loading_hopper_4"},
    {0, -4, 0, "loading_hopper_5"},
    {-1, -4, 0, "loading_hopper_6"},
    {-2, -4, 0, "loading_hopper_7"},
    {-3, -4, 0, "loading_hopper_8"},
    {4, -3, 0, "loading_hopper_9"},
    {3, -3, 0, "loading_hopper_10"},
    {2, -3, 0, "loading_hopper_11"},
    {-1, -3, 0, "loading_hopper_12"},
    {-2, -3, 0, "loading_hopper_13"},
    {-3, -3, 0, "loading_hopper_14"},
    {3, -2, 0, "loading_hopper_15"},
    {-2, -2, 0, "loading_hopper_16"},
    {3, -1, 0, "loading_hopper_17"},
    {1, -1, 0, "loading_hopper_18"},
    {0, -1, 0, "loading_hopper_19"},
    {-2, -1, 0, "loading_hopper_20"},
    {3, 0, 0, "loading_hopper_21"},
    {1, 0, 0, "loading_hopper_22"},
    {-2, 0, 0, "loading_hopper_23"},
    {3, 1, 0, "loading_hopper_24"},
    {-2, 1, 0, "loading_hopper_25"},
    {4, 2, 0, "loading_hopper_26"},
    {3, 2, 0, "loading_hopper_27"},
    {2, 2, 0, "loading_hopper_28"},
    {-1, 2, 0, "loading_hopper_29"},
    {-2, 2, 0, "loading_hopper_30"},
    {-3, 2, 0, "loading_hopper_31"},
    {4, 3, 0, "loading_hopper_32"},
    {3, 3, 0, "loading_hopper_33"},
    {2, 3, 0, "loading_hopper_34"},
    {1, 3, 0, "loading_hopper_35"},
    {0, 3, 0, "loading_hopper_36"},
    {-1, 3, 0, "loading_hopper_37"},
    {-2, 3, 0, "loading_hopper_38"},
    {-3, 3, 0, "loading_hopper_39"},
    {4, -5, 2, "loading_hopper_40"},
    {3, -5, 2, "loading_hopper_41"},
    {2, -5, 2, "loading_hopper_42"},
    {1, -5, 2, "loading_hopper_43"},
    {0, -5, 2, "loading_hopper_44"},
    {-1, -5, 2, "loading_hopper_45"},
    {-2, -5, 2, "loading_hopper_46"},
    {-3, -5, 2, "loading_hopper_47"},
    {4, -4, 2, "loading_hopper_48"},
    {3, -4, 2, "loading_hopper_49"},
    {2, -4, 2, "loading_hopper_50"},
    {1, -4, 2, "loading_hopper_51"},
    {0, -4, 2, "loading_hopper_52"},
    {-1, -4, 2, "loading_hopper_53"},
    {-2, -4, 2, "loading_hopper_54"},
    {-3, -4, 2, "loading_hopper_55"},
    {4, -3, 2, "loading_hopper_56"},
    {3, -3, 2, "loading_hopper_57"},
    {2, -3, 2, "loading_hopper_58"},
    {1, -3, 2, "loading_hopper_59"},
    {0, -3, 2, "loading_hopper_60"},
    {-1, -3, 2, "loading_hopper_61"},
    {-2, -3, 2, "loading_hopper_62"},
    {-3, -3, 2, "loading_hopper_63"},
    {4, -2, 2, "loading_hopper_64"},
    {3, -2, 2, "loading_hopper_65"},
    {2, -2, 2, "loading_hopper_66"},
    {1, -2, 2, "loading_hopper_67"},
    {0, -2, 2, "loading_hopper_68"},
    {-1, -2, 2, "loading_hopper_69"},
    {-2, -2, 2, "loading_hopper_70"},
    {-3, -2, 2, "loading_hopper_71"},
    {4, -1, 2, "loading_hopper_72"},
    {3, -1, 2, "loading_hopper_73"},
    {2, -1, 2, "loading_hopper_74"},
    {1, -1, 2, "loading_hopper_75"},
    {0, -1, 2, "loading_hopper_76"},
    {-1, -1, 2, "loading_hopper_77"},
    {-2, -1, 2, "loading_hopper_78"},
    {-3, -1, 2, "loading_hopper_79"},
    {4, 0, 2, "loading_hopper_80"},
    {3, 0, 2, "loading_hopper_81"},
    {2, 0, 2, "loading_hopper_82"},
    {1, 0, 2, "loading_hopper_83"},
    {0, 0, 2, "loading_hopper_84"},
    {-1, 0, 2, "loading_hopper_85"},
    {-2, 0, 2, "loading_hopper_86"},
    {-3, 0, 2, "loading_hopper_87"},
    {4, 1, 2, "loading_hopper_88"},
    {3, 1, 2, "loading_hopper_89"},
    {2, 1, 2, "loading_hopper_90"},
    {1, 1, 2, "loading_hopper_91"},
    {0, 1, 2, "loading_hopper_92"},
    {-1, 1, 2, "loading_hopper_93"},
    {-2, 1, 2, "loading_hopper_94"},
    {-3, 1, 2, "loading_hopper_95"},
    {4, 2, 2, "loading_hopper_96"},
    {3, 2, 2, "loading_hopper_97"},
    {2, 2, 2, "loading_hopper_98"},
    {1, 2, 2, "loading_hopper_99"},
    {0, 2, 2, "loading_hopper_100"},
    {-1, 2, 2, "loading_hopper_101"},
    {-2, 2, 2, "loading_hopper_102"},
    {-3, 2, 2, "loading_hopper_103"},
    {4, 3, 2, "loading_hopper_104"},
    {3, 3, 2, "loading_hopper_105"},
    {2, 3, 2, "loading_hopper_106"},
    {1, 3, 2, "loading_hopper_107"},
    {0, 3, 2, "loading_hopper_108"},
    {-1, 3, 2, "loading_hopper_109"},
    {-2, 3, 2, "loading_hopper_110"},
    {-3, 3, 2, "loading_hopper_111"},
    {4, 4, 2, "loading_hopper_112"},
    {3, 4, 2, "loading_hopper_113"},
    {2, 4, 2, "loading_hopper_114"},
    {1, 4, 2, "loading_hopper_115"},
    {0, 4, 2, "loading_hopper_116"},
    {-1, 4, 2, "loading_hopper_117"},
    {-2, 4, 2, "loading_hopper_118"},
    {-3, 4, 2, "loading_hopper_119"},
    {3, -4, 3, "loading_hopper_120"},
    {2, -4, 3, "loading_hopper_121"},
    {1, -4, 3, "loading_hopper_122"},
    {0, -4, 3, "loading_hopper_123"},
    {-1, -4, 3, "loading_hopper_124"},
    {-2, -4, 3, "loading_hopper_125"},
    {3, -3, 3, "loading_hopper_126"},
    {2, -3, 3, "loading_hopper_127"},
    {1, -3, 3, "loading_hopper_128"},
    {0, -3, 3, "loading_hopper_129"},
    {-1, -3, 3, "loading_hopper_130"},
    {-2, -3, 3, "loading_hopper_131"},
    {3, -2, 3, "loading_hopper_132"},
    {2, -2, 3, "loading_hopper_133"},
    {-1, -2, 3, "loading_hopper_134"},
    {-2, -2, 3, "loading_hopper_135"},
    {3, -1, 3, "loading_hopper_136"},
    {2, -1, 3, "loading_hopper_137"},
    {-1, -1, 3, "loading_hopper_138"},
    {-2, -1, 3, "loading_hopper_139"},
    {3, 0, 3, "loading_hopper_140"},
    {2, 0, 3, "loading_hopper_141"},
    {-1, 0, 3, "loading_hopper_142"},
    {-2, 0, 3, "loading_hopper_143"},
    {3, 1, 3, "loading_hopper_144"},
    {2, 1, 3, "loading_hopper_145"},
    {-1, 1, 3, "loading_hopper_146"},
    {-2, 1, 3, "loading_hopper_147"},
    {3, 2, 3, "loading_hopper_148"},
    {2, 2, 3, "loading_hopper_149"},
    {1, 2, 3, "loading_hopper_150"},
    {0, 2, 3, "loading_hopper_151"},
    {-1, 2, 3, "loading_hopper_152"},
    {-2, 2, 3, "loading_hopper_153"},
    {3, 3, 3, "loading_hopper_154"},
    {2, 3, 3, "loading_hopper_155"},
    {1, 3, 3, "loading_hopper_156"},
    {0, 3, 3, "loading_hopper_157"},
    {-1, 3, 3, "loading_hopper_158"},
    {-2, 3, 3, "loading_hopper_159"},
}

local busy = false

local function spriteName(obj)
    if obj == nil or obj.getSprite == nil then
        return nil
    end
    local spr = obj:getSprite()
    if spr == nil or spr.getName == nil then
        return nil
    end
    return spr:getName()
end

local function hasSprite(square, name)
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        if spriteName(objs:get(i)) == name then
            return true
        end
    end
    return false
end

local function isHopperName(name)
    return name ~= nil and string.sub(name, 1, 15) == "loading_hopper_"
end

local function squareAt(x, y, z)
    local cell = getCell()
    local square = cell:getGridSquare(x, y, z)
    if square == nil then
        square = cell:createNewGridSquare(x, y, z, true)
    end
    return square
end

local function bindModel(obj, name)
    if obj ~= nil and obj.setSpriteModelName ~= nil then
        obj:setSpriteModelName(name)
    end
    if obj ~= nil and obj.invalidateRenderChunkLevel ~= nil then
        obj:invalidateRenderChunkLevel(136)
    end
end

-- Drop every loading_hopper_* in the bay so a rebuild is not stuck on old meshes.
local function clearFootprint(ax, ay, az)
    local cell = getCell()
    for dx = -6, 6 do
        for dy = -6, 6 do
            for dz = 0, 3 do
                local square = cell:getGridSquare(ax + dx, ay + dy, az + dz)
                if square ~= nil then
                    local objs = square:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local obj = objs:get(i)
                        local name = spriteName(obj)
                        if isHopperName(name) and name ~= ANCHOR then
                            square:RemoveTileObject(obj)
                        end
                    end
                    if square.RecalcProperties ~= nil then
                        square:RecalcProperties()
                    end
                end
            end
        end
    end
end

local function stamp(anchor)
    if busy or anchor == nil then
        return
    end
    local data = anchor:getModData()
    if data.hopperGrid then
        return
    end
    local square = anchor:getSquare()
    if square == nil then
        return
    end
    busy = true
    local ax, ay, az = square:getX(), square:getY(), square:getZ()
    clearFootprint(ax, ay, az)
    local function place(entry, bind)
        local dest = squareAt(ax + entry[1], ay + entry[2], az + entry[3])
        if dest == nil or hasSprite(dest, entry[4]) then
            return
        end
        local obj = IsoObject.new(getCell(), dest, entry[4])
        dest:AddTileObject(obj)
        if bind then
            bindModel(obj, entry[4])
        end
        if dest.RecalcProperties ~= nil then
            dest:RecalcProperties()
        end
        if dest.RecalcAllWithNeighbours ~= nil then
            dest:RecalcAllWithNeighbours(true)
        end
    end
    for i = 1, #PIECES do
        place(PIECES[i], true)
    end
    bindModel(anchor, ANCHOR)
    data.hopperGrid = true
    if anchor.transmitModData ~= nil then
        anchor:transmitModData()
    end
    busy = false
end

local function consider(obj)
    if spriteName(obj) ~= ANCHOR then
        return
    end
    stamp(obj)
end

Events.LoadGridsquare.Add(function(square)
    if square == nil then
        return
    end
    local objs = square:getObjects()
    for i = 0, objs:size() - 1 do
        consider(objs:get(i))
    end
end)

Events.OnObjectAdded.Add(consider)

Events.OnTick.Add(function()
    local player = getPlayer()
    if player == nil then
        return
    end
    local sq = player:getCurrentSquare()
    if sq == nil then
        return
    end
    local cell = getCell()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    for dx = -6, 6 do
        for dy = -6, 6 do
            for dz = 0, 3 do
                local square = cell:getGridSquare(x + dx, y + dy, z + dz)
                if square ~= nil then
                    local objs = square:getObjects()
                    for i = 0, objs:size() - 1 do
                        consider(objs:get(i))
                    end
                end
            end
        end
    end
end)

local function registerDevHook()
    if PzDevMcpHooks == nil or PzDevMcpHooks.register == nil then
        return
    end
    PzDevMcpHooks.register("DumpTruck.placeHopper", function(payload)
        local player = getPlayer()
        if player == nil then
            return { ok = false, error = "no player" }
        end
        local square = player:getCurrentSquare()
        if square == nil then
            return { ok = false, error = "no square" }
        end
        if hasSprite(square, ANCHOR) then
            local objs = square:getObjects()
            for i = 0, objs:size() - 1 do
                local obj = objs:get(i)
                if spriteName(obj) == ANCHOR then
                    obj:getModData().hopperGrid = nil
                    stamp(obj)
                    return { ok = true, restamped = true }
                end
            end
        end
        local obj = IsoObject.new(getCell(), square, ANCHOR)
        square:AddTileObject(obj)
        bindModel(obj, ANCHOR)
        stamp(obj)
        return { ok = true, x = square:getX(), y = square:getY(), z = square:getZ() }
    end)
end

Events.OnGameStart.Add(registerDevHook)
registerDevHook()
