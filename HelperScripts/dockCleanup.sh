#!/bin/bash
# Cleans up the dock by removing unwanted items and adding desired items.
# Uses dockutil to manage the dock, so it must be installed and available at /usr/local/bin/dockutil.
# All added items are added to the end of the dock, in the order they are listed in the items_to_add array.

# Check if cleanup was already done.
if [[ -f "$HOME/Library/Logs/dockCleanup" ]]; then
	echo "Dock already cleaned up"
	exit 0
fi

DOCKPLIST="$HOME/Library/Preferences/com.apple.dock.plist"

while [[ ! -f  $DOCKPLIST ]]; do
	echo "Waiting for file"
	sleep 3
done

while [[ $(ps aux | grep $(whoami) | grep -c "Dock.app") -le 3 ]]; do
	echo "Waiting for process"
	sleep 3
done

# Extra sleep to make ABSOLUTELY CERTAIN everything is ready.
sleep 5

removeFromDock() {

	echo "Attempting to remove $1"
	while [[ $(/usr/local/bin/dockutil --find "$1" $HOME 2>&1) == *"was found"* ]]; do
    	/usr/local/bin/dockutil --remove "$1" --no-restart $DOCKPLIST 2>&1
    done

}

# Adding attempts removal first just in case one was already there.
addToDock() {

	removeFromDock "$1"
	echo "Attempting to add $1"
	while [[ ! $(/usr/local/bin/dockutil --find "$1" $HOME 2>&1) == *"was found"* ]]; do
    	/usr/local/bin/dockutil --add "$1" --position end --no-restart $DOCKPLIST 2>&1
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