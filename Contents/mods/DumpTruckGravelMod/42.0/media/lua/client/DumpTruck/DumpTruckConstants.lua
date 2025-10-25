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
DumpTruckConstants.VEHICLE_SCRIPT_NAME = "Base.VolvoFE6Dump"
DumpTruckConstants.BAG_TYPE = "Base.Gravelbag"
DumpTruckConstants.PART_NAME = "TruckBed"
DumpTruckConstants.GAP_FILLER_TILES = {
    NORTH = "blends_street_01_49",
    SOUTH = "blends_street_01_50",
    WEST = "blends_street_01_51",
    EAST = "blends_street_01_52"
}

-- Maps pairs of adjacent gravel tile directions to the appropriate blend tile direction
-- Each entry is {adjacent_directions = {dir1, dir2}, blend_direction = "DIRECTION"}
DumpTruckConstants.ADJACENT_TO_BLEND_MAPPING = {
    {
        adjacent_directions = {"EAST", "SOUTH"},
        blend_direction = "SOUTH"
    },
    {
        adjacent_directions = {"WEST", "SOUTH"},
        blend_direction = "WEST"
    },
    {
        adjacent_directions = {"NORTH", "EAST"},
        blend_direction = "EAST"
    },
    {
        adjacent_directions = {"WEST", "NORTH"},
        blend_direction = "NORTH"
    }
}

DumpTruckConstants.GRAVEL_SPRITE = "blends_street_01_55"
DumpTruckConstants.GAP_FILLER_SPRITES = "blends_street_01"
DumpTruckConstants.EDGE_BLEND_SPRITES = "blends_natural_01"

-- Tile type constants for unified metadata system
DumpTruckConstants.TILE_TYPES = {
    GAP_FILLER = "gapFiller",
    EDGE_BLEND = "edgeBlend", 
    GRAVEL = "gravel"
}

DumpTruckConstants.EDGE_BLEND_DIRECTION_OFFSETS = {
    NORTH = {8, 12},   -- Top edge + variation
    WEST = {9, 13},    -- Left edge + variation
    EAST = {10, 14},   -- Right edge + variation
    SOUTH = {11, 15}   -- Bottom edge + variation
}

return DumpTruckConstants

