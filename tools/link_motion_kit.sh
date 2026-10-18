#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Link a local Godot Motion Kit checkout into this project for the bridge tests
# and demos:  tools/link_motion_kit.sh [path/to/godot-motion-kit]
# The link is git-ignored; the audio kit itself never requires the motion kit.
set -e
cd "$(dirname "$0")/.."
src="${1:-../godot-motion-kit}"
[ -d "$src/addons/motion_kit" ] || { echo "no motion kit at $src" >&2; exit 1; }
ln -sfn "$(cd "$src/addons/motion_kit" && pwd)" addons/motion_kit
echo "linked addons/motion_kit -> $src/addons/motion_kit"
