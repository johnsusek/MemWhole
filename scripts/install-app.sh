#!/bin/sh
# Release-build MemWhole.app, install it in /Applications, and relaunch it if it was running.
set -eu
cd "$(dirname "$0")/.."

xcodegen generate --spec App/project.yml --quiet
xcodebuild -project App/MemWhole.xcodeproj -scheme MemWhole -configuration Release \
    -derivedDataPath App/.build/DerivedData -quiet build

built=App/.build/DerivedData/Build/Products/Release/MemWhole.app
installed=/Applications/MemWhole.app

was_running=no
if pgrep -x MemWhole >/dev/null; then
    was_running=yes
    pkill -x MemWhole
    while pgrep -x MemWhole >/dev/null; do sleep 0.2; done
fi

rm -rf "$installed"
ditto "$built" "$installed"
echo "Installed $installed"

if [ "$was_running" = yes ]; then
    open "$installed"
    echo "Relaunched"
fi
