local DumpTruckConstants = {}

--Misc Information
DumpTruckConstants.DUMP_KEY = 34  -- Key code for 'G'
DumpTruckConstants.UPDATE_INTERVAL = 0.5 -- how often to drop gravel in seconds
DumpTruckConstants.AXIS = {
    X = "X",
    Y = "Y",
    Z = "Z"
}

--Sprite Information
DumpTruckConstants.VEHICLE_SCRIPT_NAME = "Base.DumpTruck"
DumpTruckConstants.PART_NAME = "TruckBed"

--[[
    What the truck can pour, and what a poured tile becomes.

    Bag, floor sprite and floor type are vanilla's own triple: ISInventoryBuildMenu spills
    each bag onto these sprites and ISNaturalFloor stamps these `pouredFloor` values, so a
    road the truck lays is the same tile a player lays by hand with the same bag.

    A mixed load is spent in the order the bags sit in the bed, not in the order listed
    here, so a striped road records how the truck was packed.
]]
DumpTruckConstants.POURABLES = {
    { bag = "Base.Gravelbag", sprite = "blends_street_01_55",  floorType = "gravel" },
    { bag = "Base.Sandbag",   sprite = "blends_natural_01_5",  floorType = "sand" },
    { bag = "Base.Dirtbag",   sprite = "blends_natural_01_64", floorType = "dirt" },
}

DumpTruckConstants.POURABLE_BY_BAG = {}
DumpTruckConstants.POURABLE_BY_FLOOR_TYPE = {}
for _, pourable in ipairs(DumpTruckConstants.POURABLES) do
    DumpTruckConstants.POURABLE_BY_BAG[pourable.bag] = pourable
    DumpTruckConstants.POURABLE_BY_FLOOR_TYPE[pourable.floorType] = pourable
end

-- What a pourable bag becomes once drained, per the bags' own ReplaceOnDeplete
DumpTruckConstants.EMPTY_BAG_TYPE = "Base.EmptySandbag"

-- Maps pairs of adjacent gravel tile directions to the appropriate gap filler triangle offset
-- Each entry is {adjacent_directions = {dir1, dir2}, triangle_offset = N}
DumpTruckConstants.ADJACENT_TO_BLEND_MAPPING = {
    {
        adjacent_directions = {"EAST", "SOUTH"},
        triangle_offset = 1
    },
    {
        adjacent_directions = {"WEST", "SOUTH"},
        triangle_offset = 4
    },
    {
        adjacent_directions = {"NORTH", "EAST"},
        triangle_offset = 3
    },
    {
        adjacent_directions = {"WEST", "NORTH"},
        triangle_offset = 2
    }
}

-- Gravel alone is known by its sprite as well as by modData: it is the one poured floor
-- that wears a street tile, which no natural ground uses. Sand and dirt pour onto the same
-- tiles beaches and dirt fields are made of, so only `pouredFloor` tells those apart.
DumpTruckConstants.GRAVEL_SPRITE = DumpTruckConstants.POURABLE_BY_FLOOR_TYPE.gravel.sprite
DumpTruckConstants.EDGE_BLEND_SPRITES = "blends_natural_01"

-- Tile type constants for unified metadata system (gap fillers are just gravel with attached sprites)
DumpTruckConstants.TILE_TYPES = {
    EDGE_BLEND = "edgeBlend",
    GAP_FILLER = "gapFiller",
    GRAVEL = "gravel"
}

DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS = {
    NORTH = {8, 12},   -- Top edge + variation
    WEST = {9, 13},    -- Left edge + variation
    EAST = {10, 14},   -- Right edge + variation
    SOUTH = {11, 15}   -- Bottom edge + variation
}

-- Pour effect: overlay sprites shown briefly when gravel is placed (client-only visual)
-- Stages progress from sparse to dense; fake floor + speckle overlay hide gravel until removed
DumpTruckConstants.POUR_SPRITES = { "dumptruck_pour_00", "dumptruck_pour_005", "dumptruck_pour_01" }
DumpTruckConstants.POUR_STAGE_MS = 120

-- Snap Line: snap gravel placement to a cardinal grid line
DumpTruckConstants.SNAP_LINE_DRIFT_MAX = 3
DumpTruckConstants.SNAP_LINE_ENGAGE_THRESHOLD = 25

return DumpTruckConstants

