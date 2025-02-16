# Dump Truck Gravel Mod

A Project Zomboid mod that adds a functional dump truck capable of replacing ground tiles with gravel. This mod enhances construction and base-building capabilities by allowing players to efficiently modify terrain using a dump truck.

## Compatibility

- Requires Project Zomboid Build 42
- Single Player only (multiplayer not supported)

## Features

- Adds a fully functional dump truck to the game
- Ability to load and unload gravel
- Replace ground tiles with gravel using the dump truck bed
- Custom vehicle UI and interactions
- Seamless integration with Project Zomboid's existing mechanics

## Installation

1. Subscribe to the mod through the Steam Workshop (coming soon)
2. Or manually install by copying the mod folder to your Project Zomboid mods directory:
   ```
   [User]/Zomboid/mods/
   ```

## Usage

1. Find or spawn a dump truck in-game
2. Load the truck bed with gravel using a shovel
3. Drive to your desired location
4. Use the vehicle interaction menu to dump gravel and modify terrain

## Files Structure

- `media/lua/client/DumpTruck/` - Contains the main mod scripts
  - `DumpTruckBed.lua` - Handles truck bed functionality
  - `DumpTruckGravel.lua` - Manages gravel mechanics
  - `ISShovelGroundDumpTruck.lua` - Implements shovel interactions
  - `ISVehicleMenuDumpTruck.lua` - Adds vehicle menu options
- `media/scripts/` - Contains vehicle definitions
- `media/ui/` - Contains UI elements

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## License

This project is open source and available under the MIT License.

## Credits

Created by Brian Rutledge 