#!/bin/sh
# Packages the Roku channel as OliviaTV-roku.zip (sideload via the TV's developer page).
set -e
cd "$(dirname "$0")/../roku"
mkdir -p data
cp ../data/channels.json data/channels.json
rm -f ../OliviaTV-roku.zip
zip -qr ../OliviaTV-roku.zip manifest source components images data
