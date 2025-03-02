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
DumpTruckConstants.GRAVEL_BLEND_TILES = {
    NORTH = "blends_street_01_49",
    SOUTH = "blends_street_01_50",
    WEST = "blends_street_01_51",
    EAST = "blends_street_01_52"
}
DumpTruckConstants.GRAVEL_SPRITE = "blends_street_01_55"

DumpTruckConstants.DIRECTION_OFFSETS = {
    NORTH = {8, 12},   -- Top edge + variation
    WEST = {9, 13},    -- Left edge + variation
    EAST = {10, 14},   -- Right edge + variation
    SOUTH = {11, 15}   -- Bottom edge + variation
}

return DumpTruckConstants

