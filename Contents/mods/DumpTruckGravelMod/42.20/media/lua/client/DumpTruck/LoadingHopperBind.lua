-- Placing the anchor tile stamps the rest of the hopper.
-- Each entry is dx, dy, dz from the anchor square, then the sprite.

local ANCHOR = "loading_hopper_0"
local PIECES = {
    {4, -5, 0, "loading_hopper_1"},
    {3, -5, 0, "loading_hopper_2"},
    {2, -5, 0, "loading_hopper_3"},
    {1, -5, 0, "loading_hopper_4"},
    {0, -5, 0, "loading_hopper_5"},
    {-1, -5, 0, "loading_hopper_6"},
    {-2, -5, 0, "loading_hopper_7"},
    {-3, -5, 0, "loading_hopper_8"},
    {4, -4, 0, "loading_hopper_9"},
    {3, -4, 0, "loading_hopper_10"},
    {2, -4, 0, "loading_hopper_11"},
    {1, -4, 0, "loading_hopper_12"},
    {0, -4, 0, "loading_hopper_13"},
    {-1, -4, 0, "loading_hopper_14"},
    {-2, -4, 0, "loading_hopper_15"},
    {-3, -4, 0, "loading_hopper_16"},
    {4, -3, 0, "loading_hopper_17"},
    {3, -3, 0, "loading_hopper_18"},
    {2, -3, 0, "loading_hopper_19"},
    {1, -3, 0, "loading_hopper_20"},
    {0, -3, 0, "loading_hopper_21"},
    {-1, -3, 0, "loading_hopper_22"},
    {-2, -3, 0, "loading_hopper_23"},
    {-3, -3, 0, "loading_hopper_24"},
    {4, -2, 0, "loading_hopper_25"},
    {3, -2, 0, "loading_hopper_26"},
    {2, -2, 0, "loading_hopper_27"},
    {1, -2, 0, "loading_hopper_28"},
    {0, -2, 0, "loading_hopper_29"},
    {-1, -2, 0, "loading_hopper_30"},
    {-2, -2, 0, "loading_hopper_31"},
    {-3, -2, 0, "loading_hopper_32"},
    {4, -1, 0, "loading_hopper_33"},
    {3, -1, 0, "loading_hopper_34"},
    {2, -1, 0, "loading_hopper_35"},
    {1, -1, 0, "loading_hopper_36"},
    {0, -1, 0, "loading_hopper_37"},
    {-1, -1, 0, "loading_hopper_38"},
    {-2, -1, 0, "loading_hopper_39"},
    {-3, -1, 0, "loading_hopper_40"},
    {4, 0, 0, "loading_hopper_41"},
    {3, 0, 0, "loading_hopper_42"},
    {2, 0, 0, "loading_hopper_43"},
    {1, 0, 0, "loading_hopper_44"},
    {-1, 0, 0, "loading_hopper_45"},
    {-2, 0, 0, "loading_hopper_46"},
    {-3, 0, 0, "loading_hopper_47"},
    {4, 1, 0, "loading_hopper_48"},
    {3, 1, 0, "loading_hopper_49"},
    {2, 1, 0, "loading_hopper_50"},
    {1, 1, 0, "loading_hopper_51"},
    {0, 1, 0, "loading_hopper_52"},
    {-1, 1, 0, "loading_hopper_53"},
    {-2, 1, 0, "loading_hopper_54"},
    {-3, 1, 0, "loading_hopper_55"},
    {4, 2, 0, "loading_hopper_56"},
    {3, 2, 0, "loading_hopper_57"},
    {2, 2, 0, "loading_hopper_58"},
    {1, 2, 0, "loading_hopper_59"},
    {0, 2, 0, "loading_hopper_60"},
    {-1, 2, 0, "loading_hopper_61"},
    {-2, 2, 0, "loading_hopper_62"},
    {-3, 2, 0, "loading_hopper_63"},
    {4, 3, 0, "loading_hopper_64"},
    {3, 3, 0, "loading_hopper_65"},
    {2, 3, 0, "loading_hopper_66"},
    {1, 3, 0, "loading_hopper_67"},
    {0, 3, 0, "loading_hopper_68"},
    {-1, 3, 0, "loading_hopper_69"},
    {-2, 3, 0, "loading_hopper_70"},
    {-3, 3, 0, "loading_hopper_71"},
    {4, 4, 0, "loading_hopper_72"},
    {3, 4, 0, "loading_hopper_73"},
    {2, 4, 0, "loading_hopper_74"},
    {1, 4, 0, "loading_hopper_75"},
    {0, 4, 0, "loading_hopper_76"},
    {-1, 4, 0, "loading_hopper_77"},
    {-2, 4, 0, "loading_hopper_78"},
    {-3, 4, 0, "loading_hopper_79"},
    {4, -5, 3, "loading_hopper_80"},
    {3, -5, 3, "loading_hopper_81"},
    {2, -5, 3, "loading_hopper_82"},
    {1, -5, 3, "loading_hopper_83"},
    {0, -5, 3, "loading_hopper_84"},
    {-1, -5, 3, "loading_hopper_85"},
    {-2, -5, 3, "loading_hopper_86"},
    {-3, -5, 3, "loading_hopper_87"},
    {4, -4, 3, "loading_hopper_88"},
    {3, -4, 3, "loading_hopper_89"},
    {2, -4, 3, "loading_hopper_90"},
    {1, -4, 3, "loading_hopper_91"},
    {0, -4, 3, "loading_hopper_92"},
    {-1, -4, 3, "loading_hopper_93"},
    {-2, -4, 3, "loading_hopper_94"},
    {-3, -4, 3, "loading_hopper_95"},
    {4, -3, 3, "loading_hopper_96"},
    {3, -3, 3, "loading_hopper_97"},
    {2, -3, 3, "loading_hopper_98"},
    {1, -3, 3, "loading_hopper_99"},
    {0, -3, 3, "loading_hopper_100"},
    {-1, -3, 3, "loading_hopper_101"},
    {-2, -3, 3, "loading_hopper_102"},
    {-3, -3, 3, "loading_hopper_103"},
    {4, -2, 3, "loading_hopper_104"},
    {3, -2, 3, "loading_hopper_105"},
    {2, -2, 3, "loading_hopper_106"},
    {1, -2, 3, "loading_hopper_107"},
    {0, -2, 3, "loading_hopper_108"},
    {-1, -2, 3, "loading_hopper_109"},
    {-2, -2, 3, "loading_hopper_110"},
    {-3, -2, 3, "loading_hopper_111"},
    {4, -1, 3, "loading_hopper_112"},
    {3, -1, 3, "loading_hopper_113"},
    {2, -1, 3, "loading_hopper_114"},
    {-1, -1, 3, "loading_hopper_115"},
    {-2, -1, 3, "loading_hopper_116"},
    {-3, -1, 3, "loading_hopper_117"},
    {4, 0, 3, "loading_hopper_118"},
    {3, 0, 3, "loading_hopper_119"},
    {2, 0, 3, "loading_hopper_120"},
    {-1, 0, 3, "loading_hopper_121"},
    {-2, 0, 3, "loading_hopper_122"},
    {-3, 0, 3, "loading_hopper_123"},
    {4, 1, 3, "loading_hopper_124"},
    {3, 1, 3, "loading_hopper_125"},
    {2, 1, 3, "loading_hopper_126"},
    {1, 1, 3, "loading_hopper_127"},
    {0, 1, 3, "loading_hopper_128"},
    {-1, 1, 3, "loading_hopper_129"},
    {-2, 1, 3, "loading_hopper_130"},
    {-3, 1, 3, "loading_hopper_131"},
    {4, 2, 3, "loading_hopper_132"},
    {3, 2, 3, "loading_hopper_133"},
    {2, 2, 3, "loading_hopper_134"},
    {1, 2, 3, "loading_hopper_135"},
    {0, 2, 3, "loading_hopper_136"},
    {-1, 2, 3, "loading_hopper_137"},
    {-2, 2, 3, "loading_hopper_138"},
    {-3, 2, 3, "loading_hopper_139"},
    {4, 3, 3, "loading_hopper_140"},
    {3, 3, 3, "loading_hopper_141"},
    {2, 3, 3, "loading_hopper_142"},
    {1, 3, 3, "loading_hopper_143"},
    {0, 3, 3, "loading_hopper_144"},
    {-1, 3, 3, "loading_hopper_145"},
    {-2, 3, 3, "loading_hopper_146"},
    {-3, 3, 3, "loading_hopper_147"},
    {4, 4, 3, "loading_hopper_148"},
    {3, 4, 3, "loading_hopper_149"},
    {2, 4, 3, "loading_hopper_150"},
    {1, 4, 3, "loading_hopper_151"},
    {0, 4, 3, "loading_hopper_152"},
    {-1, 4, 3, "loading_hopper_153"},
    {-2, 4, 3, "loading_hopper_154"},
    {-3, 4, 3, "loading_hopper_155"},
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

-- Drop loading_hopper_* nearby so rebuilds are not stuck on old / overlapping meshes.
-- keep_anchor: when true, leave the ANCHOR on (ax,ay,az) alone.
local function clearFootprint(ax, ay, az, keep_anchor)
    local cell = getCell()
    for dx = -20, 20 do
        for dy = -20, 20 do
            for dz = 0, 3 do
                local square = cell:getGridSquare(ax + dx, ay + dy, az + dz)
                if square ~= nil then
                    local objs = square:getObjects()
                    for i = objs:size() - 1, 0, -1 do
                        local obj = objs:get(i)
                        local name = spriteName(obj)
                        if isHopperName(name) then
                            local same =
                                keep_anchor
                                and name == ANCHOR
                                and square:getX() == ax
                                and square:getY() == ay
                                and square:getZ() == az
                            if not same then
                                square:RemoveTileObject(obj)
                            end
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
    clearFootprint(ax, ay, az, true)
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
        local ax, ay, az = square:getX(), square:getY(), square:getZ()
        -- Scrub every hopper in range (including other anchors), then one fresh stamp.
        clearFootprint(ax, ay, az, false)
        local obj = IsoObject.new(getCell(), square, ANCHOR)
        square:AddTileObject(obj)
        bindModel(obj, ANCHOR)
        stamp(obj)
        return { ok = true, x = ax, y = ay, z = az }
    end)
end

Events.OnGameStart.Add(registerDevHook)
registerDevHook()
