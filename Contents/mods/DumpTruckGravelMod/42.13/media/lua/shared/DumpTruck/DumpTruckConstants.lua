local DumpTruckConstants = {}

-- These should come from the script ideally
DumpTruckConstants.DEFAULT_MAX_SPEED = 70.0

--Misc Information
DumpTruckConstants.MAX_DUMP_SPEED = 5.0 -- Maximum speed in km/h while dumping
DumpTruckConstants.DUMP_KEY = 34  -- Key code for 'G'
DumpTruckConstants.UPDATE_INTERVAL = 0.5 -- how often to drop gravel in seconds
DumpTruckConstants.AXIS = {
    X = "X",
    Y = "Y",
    Z = "Z"
}

--Sprite Information
DumpTruckConstants.POURED_FLOOR_TYPE = "gravel"
DumpTruckConstants.VEHICLE_SCRIPT_NAME = "Base.DumpTruck"
DumpTruckConstants.BAG_TYPE = "Base.Gravelbag"
DumpTruckConstants.PART_NAME = "TruckBed"

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

DumpTruckConstants.GRAVEL_SPRITE = "blends_street_01_55"
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

return DumpTruckConstants

