#!/usr/bin/env bash
# Nordic Hunt: Moose Country - launcher.
# Needs Godot 4.4 or newer (Arch / Omarchy:  sudo pacman -S godot).
set -e
cd "$(dirname "$(readlink -f "$0")")"

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	for candidate in godot godot4 godot-4; do
		if command -v "$candidate" >/dev/null 2>&1; then
			GODOT="$candidate"
			break
		fi
	done
fi
if [ -z "$GODOT" ]; then
	echo "Godot 4 was not found. Install it with:  sudo pacman -S godot" >&2
	exit 1
fi

# First launch, or scripts changed since Godot last indexed the project (a new
# class_name is only known after a rescan): let Godot index it.
CACHE=.godot/global_script_class_cache.cfg
if [ ! -f "$CACHE" ] || [ -n "$(find scripts -name '*.gd' -newer "$CACHE" -print -quit)" ]; then
	echo "Preparing the project..."
	"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
	touch "$CACHE"
fi

exec "$GODOT" --path . "$@"
