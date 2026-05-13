#!/bin/bash
# Clears all notifications from the Notification Center.
# Works for both single notifications and grouped notifications.

osascript <<EOAS
tell application "System Events"
	tell process "NotificationCenter"
		repeat while (window "Notification Center" exists)
			set alertGroups to first UI element of first scroll area of first group of first group of window "Notification Center"
			repeat with aGroup in alertGroups
				if (every action in aGroup) is {} then
					repeat with bGroup in aGroup
						perform (first action of first UI element of bGroup whose name contains "Close" or name contains "Clear")
						delay 0.1
					end repeat
				else
					perform (first action in aGroup whose name contains "Close" or name contains "Clear")
				end if
			end repeat
			delay 0.75
		end repeat
	end tell
end tell
EOAS