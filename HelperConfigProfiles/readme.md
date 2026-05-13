# HelperConfigProfiles

This folder contains a number of configuration profiles that are meant to be delivered via Jamf. Most of these are not strictly necessary, but are designed to faciltate an easy onboarding experience.

Each profile's UUIDs, tenant information, and Organization name have been stripped and must be provided by a system administrator before deployment. Placeholder values have been wrapped in square brackets [] for searchability.

Specific information on each configuration profile can be found below.

## Config - Google Chrome

This configuration provides a basic configuration to enroll a user's chrome browser into the enterprise environment.

* Google Chrome will auto-prompt the user to switch their default browser on launch, if not already set. (JSC can take care of this preemptively via the `defaultApp` step.)
* Privacy Sandbox Popup is disabled.
* Sign-ins are required, and are restricted to a specific set of domain patterns to enforce enterprise login for user-based settings to apply.
* A Coud Enrollment Token can also be provided to provision more device-level settings on first launch.

## Config - OneDrive

This profile auto-configures Microsoft OneDrive for immediate use, with much of the extra configuration/onboarding streamlined.

* Notifications and Managed Login Item rules pre-configured.
* Tutorials, Personal Account Login, KFM Opt-Out, and External Syncing are all disabled.
* KFM Silent Opt-In, Sync Admin Reports, Files On-Demand, and Open at Login are all enabled.
* Default Folder Location defaults to the user's home directory.
* Web Shortcut files (`.webloc`) are ignored and will not sync.

## PPPC - Jamf Setup Checklist

This profile contains a managed login item entry, along with PPPC permissions that allow JSC to manipulate UI via AppleScript and other application data via standard scripting.

## PPPC - OneDrive

Basic profile that grants OneDrive permission to access all files for syncing.