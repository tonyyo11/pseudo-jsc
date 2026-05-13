# HelperScripts

This folder contains shell scripts that can be deployed alongside JSC to provide extra functionality. All are meant to be run in user-context, though may require additional resources or PPPC configurations for JSC to properly run.

Deployment can usually be handled by placing these scripts in their own package and deployed to a location that is configured to have the proper read and execute permissions to run. If using an onboarding program such as [Jamf Setup Manager](https://github.com/jamf/Setup-Manager), this can be done by simply compiling all these scripts into a package and adding to the same policy that JSC is deployed with. 

As an example of deployment, my scripts are packaged via [Jamf Composer](https://www.jamf.com/products/jamf-composer/) and install at `/Library/Application Support/SetupChecklistHelpers/`. All files are deployed with `rwx` permissions set to `755`.

Scripts can be invoked in the background like any other shell command by appending it with the `&` operator. As these are invoked by a configuration profile, all uses of `&` be replaced with the proper escape character sequence, `&amp;`.

Specific information on each script and their requirements can be found below.

## clearNotifications.sh

This script uses AppleScript to clear all notifications that may distract a user during enrollment. Supports clearing both individual and grouped notifications.

Because this script relies on UI manipulation, **JSC must be configured using the profile found in HelperConfigProfiles to use this script.**

## dockCleanup.sh

This script provides a simple method for changing the user's dock to provide a cleaner interface. While JSC did deploy with a `Dock` step, this script can be invoked in the background as part of a `prepareScript` or `activateScript` so that the user does not have the option to skip it. Once complete, it creates an empty file at `~/Library/Logs/dockCleanup` so that it isn't run more than once.

This script requires [Kyle Crawford's dockutil](https://github.com/kcrawford/dockutil/releases/tag/3.1.3) to be installed in order to run. A copy of the pkg can be added into the same policy that JSC is deployed with so it can be installed concurrently.

## pseudo-jsc.sh

A user-context Platform SSO enforcement script for Jamf Setup Checklist, with SmartCard / PIV authentication support.

Lineage:
- Original PSSO orchestration logic and AppleScript UI walk are derived from [Kevin M. White's pseudo](https://github.com/Macjutsu/pseudo) (Apache 2.0).
- The user-context adaptation for JSC (no root, no swiftDialog, JSC-aware focus loop, Self Service URL for inventory updates) is derived from [Sebastian's JSCeudo_PSSO.sh](https://github.com/sebLuns/SetupChecklistAssets/blob/main/HelperScripts/JSCeudo_PSSO.sh).
- This fork adds back the SmartCard / PIV authentication path that JSCeudo did not support: SmartCard insertion polling, `coreautha` pairing-window awareness, and `smartCardTokenId` capture.

The script does not install or use swiftDialog — JSC's own step UI carries all user-facing messaging. It assumes the PSSO extension and configuration profile are already deployed on the target device.

On launch, `pseudo-jsc.sh` will (for SecureEnclave configurations) enable Passkey AutoFill for the configured PSSO extension; for SmartCard configurations, it will wait (with timeout) for the user to insert their SmartCard before opening the registration window. It then forces user focus on PSSO registration until either registration succeeds or the workflow times out. Additional checks keep JSC open and on the PSSO Script Step, keep Jamf Conditional Access in view if it appears, and keep the `coreautha` SmartCard PIN prompt in view during pairing.

Because this script relies on UI manipulation, **JSC must be configured using the profile found in HelperConfigProfiles to use this script.**