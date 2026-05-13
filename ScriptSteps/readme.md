# ScriptSteps

This folder contains Script Step dictionaries that can be used with JSC to complete addtional onboarding tasks.

Specific information on each Script Step can be found below.

## welcome-message

This is the standard "Welcome Message" step provided in the [Setup Checklist example plist](https://github.com/Jamf-Concepts/setup-checklist/blob/main/Examples/com.jamf.setupchecklist.plist) present in the JSC repo, but has been converted into a Script Step. With this, an administrator can configure the "Welcome" step to run a series of user-context scripts to configure additional settings or experiences that the user might not need to do manually. When configured as an `activateScript` or `prepareScript`, and when invoked as a background task using the `&` operator, this allows terminal commands or shell scripts to run immediately on launch without user intervention.

In the example provided, this is used to force a dock configuration on the user, along with clearing any notifications that may have popped up during intial login (including the Platform SSO registration prompt). The `clearNotifications.sh` script is invoked multiple times with background task delays, as there is not a reliable way of gauging when notifications spawn during the inital login process. The script then marks the step as completed, preventing it from running again should JSC be reopened or the step is selected.

## script-psso

Like the name suggests, this step invokes the `JSCeudo_PSSO.sh` script. It is configured to check to make sure that the script isn't already running in user-context before invoking it, and will mark itself completed once the PSSO user state is reported as `POUserStateNormal`. If a Jamf Conditional Access window pops up to register for Intune Device Compliance, it will stay in `suggested` status until the window is closed.

At the time of writing, Microsoft has just released a version of Company Portal that supports [Simplified PSSO](https://www.jamf.com/blog/macos-26-platform-sso-simplified-setup/) registration in Setup Assistant. This step proactively checks user registration status on launch and will mark itself completed and skip itself if the user is already registered for Platform SSO.

*Known Issue: Due to inconsistent reporting via AppleScript, the initial opening of the PSSO prompt may not be detected, and the script may close it to attempt another re-opening. This only seems to happen once-- subsequent openings of the registration window, even when performed for the first time on other accounts, will be detected as intended.*

## script-touchid

This step opens the Touch ID pane of System Settings to prompt the user to register their fingerprint. The step status will change once it detects that the user has at least one fingerprint registered, and will attempt to close System Settings once the user clicks the Continue button. 

Authenticated Guest Mode on Platform SSO is also taken into account when this step is launched. If JSC detects the current user as one of the `temporary_session` accounts used in AGM, this step will automatically mark itself complete and will skip itself.

*Known Issue: As the `bioutil` utility registers a complete biometric template partially through registration (once the prompt requests the user to register the edges of their fingerprint), it is possible for the user to click "Continue" and register only a part of their fingerprint. This also prevents JSC from closing System Settings as it will not close while the fingerprint registration prompt is open.*

## script-chrome-login

This step will open Google Chrome and then monitor the user's local state in `~/Library/Application Support/Google/Chrome/Local State` until it detects a complete setup via the `first_run_finished` key. 

Once this key is detected, JSC will automatically close Chrome and invoke `clearNotifications.sh` to clear any management related notifcations that have appeared after initial launch.

## script-onedrive

This step opens Microsoft OneDrive to allow the user to onboard themselves into syncing their files online. While this can be done without any extra configuration, this step is greatly helped by both an active Microsoft Entra Platform SSO registration, as well as the PPPC and app configurations present in HelperConfigProfiles.

This step is primarily geared towards KFM usage, so it waits until it detects the `LastKFMOptInTime` key (which happens shortly after all files in KFM folders begin syncing) before it marks itself as `completed`. From the user's perspective, this means they will see their OneDrive files appear on their desktop right as they're able to continue. Once OneDrive onboarding is complete, a short AppleScript command is sent to add OneDrive to the user's Login Items, ensuring that it will always run when the user logs in.

If your organization does not configure KFM, another key like `AccountInfo_Business1.UserEmail` may be used, though many of these keys will populate before setup is actually complete and may provide an adverse effect for users who click "Continue" before setup is finished.

*Known Issue: OneDrive's startup time on first launch is wildly inconsistent, ranging from immediately to up to two minutes before the login window is visible. As this process can usually involve multiple changing menu bar icons and login window decorations, I suspect that this may be due to the "Personal" version of OneDrive launching intially, waiting before another process kicks in to cause it to close and relaunch as the "Enterprise" version. I'm unaware of any command or method to invoke the latter immediately if this is the case.*