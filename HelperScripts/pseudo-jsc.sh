#!/bin/bash
# pseudo-jsc
# Platform SSO enforcement helper for Jamf Setup Checklist (user context).
# Adds SmartCard / PIV authentication support on top of the user-context base.
#
# Upstream lineage:
#   - https://github.com/Macjutsu/pseudo (Apache-2.0, by Kevin M. White) — original PSSO logic
#   - https://github.com/sebLuns/SetupChecklistAssets (by Sebastian) — user-context adaptation for JSC
#
# Licensed under the Apache License, Version 2.0. See LICENSE.

# The next line disables specific ShellCheck codes (https://github.com/koalaman/shellcheck) for the entire script.
# Matches the upstream pseudo convention for known-safe patterns (escape-char in tr, jamf binary stdout, pluginkit array splitting).
# shellcheck disable=SC1003,SC2012,SC2024,SC2207

# pipefail and nounset only — errexit would abort on the script's intentional non-zero
# exits (killall of optional processes, dscl/PlistBuddy reads against missing keys).
set -uo pipefail

# MARK: *** Startup Workflow ***
################################################################################

# Set default parameters that are used throughout the script.
set_defaults() {
	
	# Optionally (after succesfull Platform SSO enrollment) update Jamf Pro inventory.
	# Any other value besides "TRUE" will disable this option.
	UPDATE_JAMF_PRO="FALSE"
	readonly UPDATE_JAMF_PRO

	# Since the recon command can't be used in user context, the inventory must be updated using 
	# a Self Service policy with Maintenance > Update Inventory configured. 
	# The policy ID goes here to trigger using the JSS URL Schema.
	UPDATE_INVENTORY_POLICY_ID="1"
	readonly UPDATE_INVENTORY_POLICY_ID

	# Name of the JSS app to kill once the policy is triggered.
	SELF_SERVICE_APP_NAME="Self Service+"
	readonly SELF_SERVICE_APP_NAME

	# Trigger an additional request to register for the Intune Device Compliance integration.
	# Jamf has long since added support for silent registration for Compliance-available devices during PSSO.
	# You shouldn't need to enable this.
	MANUAL_DEVICE_COMPLIANCE_REGISTRATION="FALSE"
	readonly MANUAL_DEVICE_COMPLIANCE_REGISTRATION
	
	# *** The remaining parameters are NOT OPTIONAL but can be modified to better fit your workflow. ***
	################################################################################

	JSC_STEP_LABEL="script-psso"
	readonly JSC_STEP_LABEL

	# Number of seconds to wait for an overall workflow stage (SmartCard insertion, registration loop, pairing) to complete.
	# Bounds the outer while loops so a stuck workflow does not busy-loop forever.
	TIMEOUT_WORKFLOW_SECONDS=300
	readonly TIMEOUT_WORKFLOW_SECONDS

	# Number of seconds to wait for a system dialog (System Settings, AppSSOAgent window) to open.
	# Bounds the AppleScript wait loops inside open_psso_registration.
	TIMEOUT_OPEN_SECONDS=10
	readonly TIMEOUT_OPEN_SECONDS

	# Path to the log for the main pseudo workflow:
	PSEUDO_LOG="$HOME/Library/Logs/pseudo.log"
	readonly PSEUDO_LOG
	
	# Path to the local Extensible SSO managed PLIST.
	SSO_MANAGED_PLIST="/Library/Managed Preferences/com.apple.extensiblesso.plist"
	readonly SSO_MANAGED_PLIST
	
	# Path to the Jamf Pro conditional access binary:
	JAMF_PRO_AAD_BINARY="/usr/local/jamf/bin/jamfAAD"
	readonly JAMF_PRO_AAD_BINARY
}

# Append input to the command line and log located at ${PSEUDO_LOG}.
# Always returns 0 so a write failure on ${PSEUDO_LOG} (with pipefail) does not break
# the script's `log_pseudo "..." && flag="TRUE"` error-marking pattern.
log_pseudo() {
	echo -e "$(date +"%a %b %d %T") $(hostname -s) $(basename "$0")[$$]: $*" | tee -a "${PSEUDO_LOG}"
	return 0
}

# Exit the script with no errors.
exit_success() {
	log_pseudo "**** EXIT SUCCESS ****"
	exit 0
}

# Prepare pseudo by checking for system, Platform SSO config, and user statuses. This function will exit if any prerequisite isn't succesful.
workflow_startup() {
	local workflow_startup_error
	workflow_startup_error="FALSE"

	set_defaults

	# jq is a third-party dependency. Without it, app-sso parsing silently produces
	# empty strings and the workflow falls through to a misleading "FALSE" state.
	if ! command -v jq >/dev/null 2>&1; then
		log_pseudo "Error: jq is required but not installed."
		workflow_startup_error="TRUE"
	fi

	current_user_account_name=$(stat -f "%Su" /dev/console)

	psso_extension_identifier=$(/usr/libexec/PlistBuddy -c "Print :ExtensionIdentifier" "${SSO_MANAGED_PLIST}" 2> /dev/null)
	psso_login_type=$(/usr/libexec/PlistBuddy -c "Print :PlatformSSO:AuthenticationMethod" "${SSO_MANAGED_PLIST}" 2> /dev/null)
	psso_display_name=$(/usr/libexec/PlistBuddy -c "Print :PlatformSSO:AccountDisplayName" "${SSO_MANAGED_PLIST}" 2> /dev/null)
	
	# Platform SSO extension application checks.
	if [[ "${psso_extension_identifier}" == "com.microsoft.CompanyPortalMac.ssoextension" ]]; then
		if [[ -e "/Applications/Company Portal.app" ]]; then
			[[ -n "${psso_display_name}" ]] && log_pseudo "Status: Platform SSO configuration for Entra ID using ${psso_login_type} authentication with the display name of \"${psso_display_name}\"."
			[[ -z "${psso_display_name}" ]] && log_pseudo "Status: Platform SSO configuration for Entra ID using ${psso_login_type} authentication."
		else
			log_pseudo "Error: The required Platform SSO software Company Portal.app is not installed." && workflow_startup_error="TRUE"
		fi
	fi
	if [[ "${psso_extension_identifier}" == "com.okta.mobile.auth-service-extension" ]]; then
		if [[ -e "/Applications/Okta Verify.app" ]]; then
			[[ -n "${psso_display_name}" ]] && log_pseudo "Status: Platform SSO configuration for Okta using ${psso_login_type} authentication with the display name of \"${psso_display_name}\"."
			[[ -z "${psso_display_name}" ]] && log_pseudo "Status: Platform SSO configuration for Okta using ${psso_login_type} authentication."
		else
			log_pseudo "Error: The required Platform SSO software Okta Verify.app is not installed." && workflow_startup_error="TRUE"
		fi
	fi
	if [[ "${workflow_startup_error}" == "TRUE" ]]; then
		log_pseudo "Error: Startup workflow failed."
		exit 1
	fi
}

# MARK: *** Jamf Pro Integration ***
################################################################################

# Update Jamf Pro device compliance and inventory if workflow was successful.
jamf_pro_update_inventory() {
	[[ ! -e "/Applications/${SELF_SERVICE_APP_NAME}.app" ]] && log_pseudo "Error: Could not locate the Self Service app in the Applications folder" && update_inventory_error="TRUE"
	if [[ "${psso_workflow_active}" == "TRUE" ]]; then
		log_pseudo "Status: Updating Jamf Pro inventory..."
		open -g "jamfselfservice://content?entity=policy&id=${UPDATE_INVENTORY_POLICY_ID}&action=execute"
		sleep 5
		killall "${SELF_SERVICE_APP_NAME}"
	fi
}

jamf_pro_manual_comliance_registration() {
	[[ ! -e "${JAMF_PRO_AAD_BINARY}" ]] && log_pseudo "Error: Could not locate the Jamf Pro AAD binary in the expected location: ${JAMF_PRO_AAD_BINARY}" && manual_compliance_error="TRUE"
	if [[ "${psso_workflow_active}" == "TRUE" ]]; then
		log_pseudo "Status: Gathering Jamf Pro device compliance information..."
		local jamf_aad_response
		jamf_aad_response=$("${JAMF_PRO_AAD_BINARY}" gatherAADInfo 2>&1)
		if [[ $(echo "${jamf_aad_response}" | grep -c 'AAD ID acquired') -gt 0 ]]; then
			log_pseudo "Status: Jamf Pro device compilance information successfully updated."
		else
			log_pseudo "Error: Could not gather Jamf Pro device compilance information:\n${jamf_aad_response}" && manual_compliance_error="TRUE"
		fi
	fi
}


# MARK: *** Platform SSO Workflow ***
################################################################################

# Check to see if the current user is registered for Platform SSO and set the corresponding state variables.
# Sets: psso_user_status_dscl, psso_user_status_login_name, psso_user_status_state, psso_user_status_smartcard_token_id.
check_psso_user_status() {
	local dscl_result
	dscl_result=$(dscl . read /Users/"${current_user_account_name}" dsAttrTypeStandard:AltSecurityIdentities 2> /dev/null | awk -F'SSO:' '/PlatformSSO/ {print $2}')
	if [[ -n "${dscl_result}" ]]; then
		psso_user_status_dscl="${dscl_result}"
		local app_sso_response
		app_sso_response=$(app-sso platform -s)
		# `tr -d '\\'` strips escape characters that newer macOS versions add to app-sso output and that break jq parsing.
		local user_config_section
		user_config_section=$(echo "${app_sso_response}" | sed -e '1,/User Configuration:/d' | tr -d '\\')
		psso_user_status_login_name=$(echo "${user_config_section}" | jq -r '.userLoginConfiguration.loginUserName' 2> /dev/null)
		psso_user_status_state=$(echo "${user_config_section}" | jq -r '.state' 2> /dev/null)
		[[ $(echo "${psso_login_type}" | grep -c 'SmartCard') -gt 0 ]] && psso_user_status_smartcard_token_id=$(echo "${user_config_section}" | jq -r '.smartCardTokenId' 2> /dev/null)
	fi
	[[ -z "${dscl_result}" ]] && psso_user_status_dscl="FALSE"
	[[ -z "${psso_user_status_login_name}" ]] && psso_user_status_login_name="FALSE"
	# Match any state containing "Normal" so future Apple format variations don't break the check.
	[[ "${psso_user_status_state}" != *Normal* ]] && psso_user_status_state="FALSE"
	[[ -z "${psso_user_status_smartcard_token_id}" ]] && psso_user_status_smartcard_token_id="FALSE"
}

# Pre-enable relevant password AutoFill extensions when SecureEnclave is the set Auth Method.
enable_psso_autofill_extensions() {
	local previous_ifs
	previous_ifs="${IFS}"
	IFS=$'\n'
	local plugin_kit_response
	[[ "${psso_extension_identifier}" == "com.microsoft.CompanyPortalMac.ssoextension" ]] && plugin_kit_response=($(pluginkit -m 2> /dev/null | grep 'com.microsoft.CompanyPortalMac'))
	[[ "${psso_extension_identifier}" == "com.okta.mobile.auth-service-extension" ]] && plugin_kit_response=($(pluginkit -m 2> /dev/null | grep 'com.okta.mobile'))
	for plugin_kit_item in "${plugin_kit_response[@]}"; do
		[[ $(echo "${plugin_kit_item}" | grep -c '+') -gt 0 ]] && log_pseudo "Status: The AutoFill extension with ID $(echo "${plugin_kit_item}" | awk -F' ' '{print $2}' | sed -e 's/(.*$//') is already enabled."
		if [[ $(echo "${plugin_kit_item}" | grep -c '+') -eq 0 ]]; then
			log_pseudo "Status: Enabling AutoFill extension with ID $(echo "${plugin_kit_item}" | awk -F' ' '{print $1}' | sed -e 's/(.*$//')."
			pluginkit -e use -i "$(echo "${plugin_kit_item}" | awk -F' ' '{print $1}' | sed -e 's/(.*$//')" > /dev/null 2>&1
		fi
	done
	IFS="${previous_ifs}"
}

# Check the status of Platform SSO registration dialog and return its status as "OPEN", "ACTIVE", "AUTOFILL", "CLOSE", or "FALSE".
# Since this script does not rely on Swift Dialog, most of this is unused aside for checking whether or not PSSO is active
check_psso_registration_status() {
	local psso_registration_status_result
	psso_registration_status_result=$(osascript 2> /dev/null <<EOAS
if application "AppSSOAgent" is running then
	tell application "System Events"
		set windowCount to count of every window of application process "AppSSOAgent"
		if windowCount is greater than 1 then
			repeat with i from 1 to windowCount
				set allElements to entire contents of window i of application process "AppSSOAgent"
				repeat with aElement in allElements
					if name of aElement contains "autofill" then
						return "AUTOFILL"
					end if
				end repeat
			end repeat
			return "ACTIVE"
		else if windowCount is equal to 1 then
			if (count of every sheet of window 1 of application process "AppSSOAgent") is greater than 0 then
				return "ACTIVE"
			else -- No open sheets.
				if (count of every button of window 1 of application process "AppSSOAgent") is greater than 1 then
					return "OPEN"
				else -- Only one button.
					return "CLOSE"
				end if
			end if
		else -- No open windows.
			return "FALSE"
		end if
	end tell
else
	return "FALSE"
end if
EOAS
	)
	echo "${psso_registration_status_result}"
}

# Check whether the SmartCard authentication window (coreautha) is open. Returns "TRUE" or "FALSE".
# Used to detect the PIN prompt during initial unlock and the pairing dialog after PSSO registration starts.
check_psso_smartcard_auth_status() {
	local psso_smartcard_auth_active_result
	psso_smartcard_auth_active_result=$(osascript 2> /dev/null <<EOAS
tell application "System Events"
	if exists process "coreautha" then
		if exists window 1 of application process "coreautha" then
			return "TRUE"
		else
			return "FALSE"
		end if
	else
		return "FALSE"
	end if
end tell
EOAS
	)
	echo "${psso_smartcard_auth_active_result}"
}

# Checks if JSC is active and set to the proper step.
check_jsc_active(){
	local jsc_active_result
	jsc_active_result=$(osascript <<EOAS
tell application "System Events"
	if exists process "Setup Checklist" then
		if (exists window 1 of application process "Setup Checklist")
			return "TRUE"
		else
			return "FALSE"
		end if
	else
		return "FALSE"
	end if
end tell
EOAS
	)

	if [[ "${jsc_active_result}" == "TRUE" &&  $(/usr/local/bin/setupchecklist current) != "${JSC_STEP_LABEL}" ]]; then
		echo "FALSE"
	else
		echo "${jsc_active_result}"
	fi
}

# killall is used because of unexpected behavior with the launch command while process is active with no window
open_jsc() {
	killall "Setup Checklist"
	/usr/local/bin/setupchecklist launch
	/usr/local/bin/setupchecklist goto "${JSC_STEP_LABEL}"
}

# Open the Platform SSO registration window. Returns "TRUE" on success or "FALSE" if any wait
# step exceeds ${TIMEOUT_OPEN_SECONDS}. The outer workflow uses this result to retry or exit.
open_psso_registration() {
	killall "AppSSOAgent" 2>&1
	killall "System Settings" 2>&1
	open "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
	local open_psso_registration_result
	open_psso_registration_result=$(osascript 2> /dev/null <<EOAS
set openTimeout to (current date) + ${TIMEOUT_OPEN_SECONDS}
tell application "System Events"
	repeat while not (exists window 1 of application process "System Settings")
		delay 0.1
		if (current date) > openTimeout then return "FALSE"
	end repeat
	tell application process "System Settings" to set frontmost to true
	repeat while not (exists button 2 of group 2 of scroll area 1 of group 1 of group 3 of splitter group 1 of group 1 of window 1 of application process "System Settings")
		delay 0.1
		if (current date) > openTimeout then return "FALSE"
	end repeat
	tell button 2 of group 2 of scroll area 1 of group 1 of group 3 of splitter group 1 of group 1 of window 1 of application process "System Settings" to perform action "AXPress"
	repeat while not (exists button 1 of group 2 of scroll area 1 of group 1 of sheet 1 of window 1 of application process "System Settings")
		delay 0.1
		if (current date) > openTimeout then return "FALSE"
	end repeat
	tell button 1 of group 2 of scroll area 1 of group 1 of sheet 1 of window 1 of application process "System Settings" to perform action "AXPress"
	repeat while not (exists window 1 of application process "AppSSOAgent")
		delay 0.1
		if (current date) > openTimeout then return "FALSE"
	end repeat
	tell application "System Settings" to quit
	return "TRUE"
end tell
EOAS
	)
	echo "${open_psso_registration_result}"
}

# Hide all other visible applications so only the Platform SSO registration window is visible.
# `coreautha` is preserved so the SmartCard PIN prompt and pairing dialog stay on screen;
# when its window exists, it takes frontmost priority over the Single Sign-On window.
focus_psso_registration() {
	osascript <<EOAS
tell application "Finder"
	if (count of windows) is not 0 then
		tell application "Finder" to close every window
		delay 0.1
	end if
end tell
tell application "System Events"
	set visibleApps to every process whose visible is true and name is not "AppSSOAgent" and name is not "Jamf Conditional Access" and name is not "Single Sign-On" and name is not "Setup Checklist" and name is not "coreautha" and name is not "Finder"
	repeat with anApp in visibleApps
		tell anApp
			set visible to false
		end tell
		delay 0.1
	end repeat
	if (exists window 1 of application process "coreautha") then
		tell process "coreautha" to set frontmost to true
	else
		tell process "Single Sign-On" to set frontmost to true
	end if
end tell
EOAS

}

# The full workflow to check Platform SSO status and if required open interfaces to register with Platform SSO.
# Handles SecureEnclave, Password, and SmartCard authentication paths. For SmartCard, waits for card
# insertion before opening registration and waits for the coreautha pairing window to close after.
workflow_psso() {
	local workflow_psso_error
	workflow_psso_error="FALSE"

	# Initialize global state vars before any reference. Required under `set -u`:
	# psso_workflow_active is otherwise only set conditionally inside the workflow.
	psso_workflow_active="FALSE"
	psso_user_status_dscl="FALSE"
	psso_user_status_login_name="FALSE"
	psso_user_status_state="FALSE"
	psso_user_status_smartcard_token_id="FALSE"

	check_psso_user_status
	# Attempt an immediate open as AppleScript checks cause a delay in JSC.
	if [[ "${psso_user_status_dscl}" == "FALSE" ]] || [[ "${psso_user_status_state}" == "FALSE" ]]; then
		[[ "${psso_login_type}" == "UserSecureEnclaveKey" ]] && enable_psso_autofill_extensions
		psso_workflow_active="TRUE"
	fi

	# SmartCard pre-registration: don't drive the System Settings UI until the user has inserted their card.
	if [[ "${psso_workflow_active}" == "TRUE" ]] && [[ $(echo "${psso_login_type}" | grep -c 'SmartCard') -gt 0 ]]; then
		if [[ $(security list-smartcards 2>&1 | grep -c "No smartcards found.") -gt 0 ]]; then
			log_pseudo "Status: Waiting for SmartCard insertion with a ${TIMEOUT_WORKFLOW_SECONDS} second timeout..."
			/usr/local/bin/setupchecklist step "${JSC_STEP_LABEL}" title "Insert your SmartCard..."
			local smartcard_wait_start
			smartcard_wait_start=$(date +%s)
			while [[ $(security list-smartcards 2>&1 | grep -c "No smartcards found.") -gt 0 ]]; do
				if [[ $(( smartcard_wait_start + TIMEOUT_WORKFLOW_SECONDS )) -lt $(date +%s) ]]; then
					log_pseudo "Error: SmartCard insertion timed out after ${TIMEOUT_WORKFLOW_SECONDS} seconds."
					workflow_psso_error="TRUE"
					break
				fi
				focus_psso_registration
				sleep 1
			done
			/usr/local/bin/setupchecklist step "${JSC_STEP_LABEL}" title "Register for Platform SSO"
			[[ "${workflow_psso_error}" == "FALSE" ]] && log_pseudo "Status: SmartCard detected. Continuing Platform SSO registration workflow."
		else
			log_pseudo "Status: SmartCard already attached. Continuing Platform SSO registration workflow."
		fi
	fi

	# Main registration loop, bounded by TIMEOUT_WORKFLOW_SECONDS.
	local workflow_start_epoch
	workflow_start_epoch=$(date +%s)
	while [[ "${workflow_psso_error}" == "FALSE" ]] && { [[ "${psso_user_status_dscl}" == "FALSE" ]] || [[ "${psso_user_status_state}" == "FALSE" ]]; }; do
		if [[ $(( workflow_start_epoch + TIMEOUT_WORKFLOW_SECONDS )) -lt $(date +%s) ]]; then
			log_pseudo "Error: Platform SSO registration workflow timed out after ${TIMEOUT_WORKFLOW_SECONDS} seconds."
			workflow_psso_error="TRUE"
			break
		fi
		if [[ "$(check_psso_registration_status)" == "FALSE" ]]; then
			log_pseudo "Status: Attempting to open Platform SSO registration..."
			if [[ "$(open_psso_registration)" == "FALSE" ]]; then
				log_pseudo "Error: Opening Platform SSO registration timed out after ${TIMEOUT_OPEN_SECONDS} seconds."
				workflow_psso_error="TRUE"
				break
			fi
		fi
		if [[ "$(check_jsc_active)" == "FALSE" ]]; then
			log_pseudo "Status: Attempting to open Jamf Setup Checklist..."
			open_jsc
			[[ "$(check_jsc_active)" == "FALSE" ]] && log_pseudo "Error: Unable to open Jamf Setup Checklist."
		fi
		focus_psso_registration
		sleep 1
		check_psso_user_status
	done

	# SmartCard pairing: after registration is reported normal, the coreautha PIN/pairing window may still be open.
	if [[ "${workflow_psso_error}" == "FALSE" ]] && [[ "${psso_workflow_active}" == "TRUE" ]] && [[ $(echo "${psso_login_type}" | grep -c 'SmartCard') -gt 0 ]] && [[ "$(check_psso_smartcard_auth_status)" == "TRUE" ]]; then
		log_pseudo "Status: Waiting for SmartCard pairing to complete with a ${TIMEOUT_WORKFLOW_SECONDS} second timeout..."
		local pairing_start_epoch
		pairing_start_epoch=$(date +%s)
		while [[ "$(check_psso_smartcard_auth_status)" == "TRUE" ]]; do
			if [[ $(( pairing_start_epoch + TIMEOUT_WORKFLOW_SECONDS )) -lt $(date +%s) ]]; then
				log_pseudo "Error: SmartCard pairing timed out after ${TIMEOUT_WORKFLOW_SECONDS} seconds."
				workflow_psso_error="TRUE"
				break
			fi
			focus_psso_registration
			sleep 1
		done
		[[ "${workflow_psso_error}" == "FALSE" ]] && log_pseudo "Status: SmartCard pairing complete."
	fi

	# Final status reporting.
	if [[ "${workflow_psso_error}" == "TRUE" ]]; then
		log_pseudo "Error: Platform SSO workflow did not complete successfully."
		return 1
	elif [[ "${psso_workflow_active}" == "TRUE" ]]; then
		local registration_summary
		registration_summary="Platform SSO is now registered for local user ${current_user_account_name} to account ${psso_user_status_login_name}"
		# Truncate the SmartCard token ID before logging: full token + UPN in a user-readable
		# log is more identity correlation than is needed for diagnosing registration.
		if [[ "${psso_user_status_smartcard_token_id}" != "FALSE" ]]; then
			local token_suffix="${psso_user_status_smartcard_token_id: -8}"
			registration_summary="${registration_summary} (SmartCard token: …${token_suffix})"
		fi
		log_pseudo "Status: ${registration_summary}."
	else
		log_pseudo "Status: Platform SSO is already registered for local user ${current_user_account_name} to account ${psso_user_status_login_name}."
	fi
}

# MARK: *** Main Workflow ***
################################################################################

main() {
	workflow_startup # This function only completes if the system and user are ready to complete further workflows.
	workflow_psso # Returns 0 on success or 1 if PSSO registration did not complete (timeout, missing SmartCard, etc.).
	local workflow_psso_result=$?

	update_inventory_error="FALSE"
	manual_compliance_error="FALSE"

	# Only run post-PSSO actions when PSSO actually succeeded. Firing a Self Service inventory policy
	# after a failed registration is wasteful and misleads downstream reporting.
	if [[ ${workflow_psso_result} -eq 0 ]]; then
		[[ "${UPDATE_JAMF_PRO}" == "TRUE" ]] && jamf_pro_update_inventory
		[[ "${MANUAL_DEVICE_COMPLIANCE_REGISTRATION}" == "TRUE" ]] && jamf_pro_manual_comliance_registration
	else
		log_pseudo "Status: Skipping post-PSSO inventory and compliance actions because the Platform SSO workflow did not complete successfully."
	fi

	[[ "${update_inventory_error}" == "TRUE" ]] && log_pseudo "Error: Unable to complete requested inventory update."
	[[ "${manual_compliance_error}" == "TRUE" ]] && log_pseudo "Error: Unable to complete requested manual device compliance."
}

main "$@"
exit_success