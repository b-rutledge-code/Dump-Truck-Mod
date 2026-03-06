--[[
    DumpTruckGravelMod - Mod Options (client)

    Registers the "Allow dump truck in world spawn" option so it appears in
    Options → Mod Options. The value is stored in ModOptions.ini and read by
    VehicleZoneDistribution_DumpTruck.lua (shared) to decide whether to add
    the dump truck to vehicle spawn zones.
]]
if PZAPI and PZAPI.ModOptions then
    local opts = PZAPI.ModOptions:create("DumpTruckGravelMod", "Dump Truck Gravel Mod")
    opts:addTickBox(
        "AllowDumpTruckInWorldSpawn",
        "Allow dump truck in world spawn",
        true,
        "If unchecked, dump trucks will not be added to vehicle spawn zones (admin spawn only)."
    )
end
