#!/bin/bash
# Script to deploy the mod to Zomboid/Mods with a clean target directory
TARGET_DIR="$HOME/Zomboid/Mods/DumpTruckGravelMod"

# Remove the target directory if it exists
if [ -d "$TARGET_DIR" ]; then
    rm -rf "$TARGET_DIR"
    echo "🗑️  Removed existing mod directory"
fi

# Copy the mod files to a fresh directory
cp -rf Contents/mods/DumpTruckGravelMod "$HOME/Zomboid/Mods/"
echo "✅ Mod copied to $TARGET_DIR"

# Deploy to server
echo ""
echo "🚀 Deploying to server..."
./deploy_server.sh