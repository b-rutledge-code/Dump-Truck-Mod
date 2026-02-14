# Dump Truck Gravel Mod - Requirements

## Overview

A vehicle that allows players to build gravel roads by driving and pouring gravel.

---

## The Vehicle

- A dump truck with a functional truck bed for carrying gravel
- Spawns naturally in the world in appropriate locations
- Some trucks spawn pre-loaded with gravel, others spawn empty

## Gravel Supply

- Gravel is a consumable resource stored in the truck bed
- Players can load gravel into the truck

## Road Building

- Player activates dump mode while driving
- Gravel is deposited behind the truck as it moves
- Road width is configurable by the player
- Dumping only works while the truck is in motion and below a speed threshold

## Road Appearance

- Gravel roads replace the existing terrain
- Roads blend naturally with surrounding terrain (no hard edges)
- Diagonal roads and corners have no gaps or holes

## Road Removal

- Players can remove gravel roads using appropriate tools
- Removing gravel restores the original terrain

## Multiplayer

- Road changes sync between all players in real-time
- Visual elements (blends, corners) sync between all players

## Constraints (By Design)
- Only the driver can control dumping
- Truck must be moving to dump
- Cannot pour gravel on invalid surfaces (water, indoors)
- Cannot pour on top of existing gravel roads
