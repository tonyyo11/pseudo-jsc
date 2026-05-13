#!/bin/bash
# Cleans up the dock by removing unwanted items and adding desired items.
# Uses dockutil to manage the dock, so it must be installed and available at /usr/local/bin/dockutil.
# All added items are added to the end of the dock, in the order they are listed in the items_to_add array.

# pipefail and nounset only — errexit would abort on intentional non-zero exits
# (killall Dock when not running, dockutil --remove during transient retry failures).
set -uo pipefail

readonly DOCKUTIL="/usr/local/bin/dockutil"
readonly WAIT_TIMEOUT_SECONDS=120

if [[ ! -x "${DOCKUTIL}" ]]; then
	echo "Error: dockutil not found at ${DOCKUTIL}" >&2
	exit 1
fi

# Check if cleanup was already done.
if [[ -f "${HOME}/Library/Logs/dockCleanup" ]]; then
	echo "Dock already cleaned up"
	exit 0
fi

DOCKPLIST="${HOME}/Library/Preferences/com.apple.dock.plist"
readonly DOCKPLIST

wait_start=$(date +%s)
while [[ ! -f "${DOCKPLIST}" ]]; do
	if (( $(date +%s) - wait_start > WAIT_TIMEOUT_SECONDS )); then
		echo "Error: timed out waiting for ${DOCKPLIST} after ${WAIT_TIMEOUT_SECONDS}s" >&2
		exit 1
	fi
	echo "Waiting for file"
	sleep 3
done

wait_start=$(date +%s)
while [[ $(pgrep -u "$(whoami)" -x Dock | wc -l) -lt 1 ]]; do
	if (( $(date +%s) - wait_start > WAIT_TIMEOUT_SECONDS )); then
		echo "Error: timed out waiting for Dock process after ${WAIT_TIMEOUT_SECONDS}s" >&2
		exit 1
	fi
	echo "Waiting for process"
	sleep 3
done

# Extra sleep to make ABSOLUTELY CERTAIN everything is ready.
sleep 5

removeFromDock() {

	echo "Attempting to remove $1"
	while [[ $("${DOCKUTIL}" --find "$1" "${HOME}" 2>&1) == *"was found"* ]]; do
		"${DOCKUTIL}" --remove "$1" --no-restart "${DOCKPLIST}" 2>&1
	done

}

# Adding attempts removal first just in case one was already there.
addToDock() {

	removeFromDock "$1"
	echo "Attempting to add $1"
	while [[ ! $("${DOCKUTIL}" --find "$1" "${HOME}" 2>&1) == *"was found"* ]]; do
		"${DOCKUTIL}" --add "$1" --position end --no-restart "${DOCKPLIST}" 2>&1
	done

}

# Items being removed can be done by label, i.e. "TV", "Games", etc.
items_to_remove=(
	"Safari"
	"Messages"
	"Mail"
	"Maps"
	"Photos"
	"FaceTime"
	"Phone"
	"Contacts"
	"TV"
	"Music"
	"Games"
	"App Store"
	"iPhone Mirroring"
)

# Items being added must be added by path, i.e. "/Applications/Self Service+.app"
items_to_add=(
	"/Applications/Self Service+.app"
	"/Applications/Google Chrome.app"
)

for item in "${items_to_remove[@]}"; do
	removeFromDock "${item}"
done

for item in "${items_to_add[@]}"; do
	addToDock "${item}"
done

# Restart dock to apply changes
killall Dock

# Set file to mark dock as cleaned up 
touch "$HOME/Library/Logs/dockCleanup"