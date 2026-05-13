# pseudo-jsc

Platform SSO enforcement for [Jamf Setup Checklist](https://github.com/Jamf-Concepts/setup-checklist), including SmartCard / PIV authentication.

`pseudo-jsc` is a fork that combines two upstream projects:

- [**Macjutsu/pseudo**](https://github.com/Macjutsu/pseudo) by Kevin M. White — the original Platform SSO registration enforcement script. Apache 2.0.
- [**sebLuns/SetupChecklistAssets**](https://github.com/sebLuns/SetupChecklistAssets) by Sebastian — adapts pseudo to run in user context under Jamf Setup Checklist, replacing swiftDialog with JSC's native step UI and replacing the direct `jamf` binary calls with the `jamfselfservice://` URL scheme so it can run without root.

The fork adds **SmartCard / PIV** support that the JSC-adapted version did not include: SmartCard insertion polling with a configurable timeout, `coreautha` pairing-window awareness in the focus loop, and `smartCardTokenId` capture for logging. Targeted at environments that enforce PSSO with PIV / CAC rather than Secure Enclave or password authentication.

## Repository Layout

This repo is divided into three sections that work in tandem with each other:

- **HelperConfigProfiles** — configuration profiles delivered via your MDM. Provides the PPPC permissions JSC needs to drive AppleScript-based UI automation, and managed preferences for the apps JSC onboards (Chrome, OneDrive).
- **HelperScripts** — shell scripts invoked by JSC step callbacks. `pseudo-jsc.sh` is the Platform SSO workflow; the others (`clearNotifications.sh`, `dockCleanup.sh`) are JSC quality-of-life utilities inherited from upstream.
- **ScriptSteps** — XML `<dict>` fragments to embed in your JSC configuration profile's `steps` array.

See each folder's `readme.md` for asset-specific details.

## Customization before deployment

- Configuration profiles contain `[bracketed]` placeholders (UUIDs, your organization name, code-signing OIDs, optional MDM tenant IDs) that you must replace before deploying.
- `pseudo-jsc.sh` has runtime knobs near the top in `set_defaults()`. The most likely to need attention:
  - `UPDATE_JAMF_PRO` — set `"TRUE"` if you want post-PSSO inventory + compliance updates.
  - `UPDATE_INVENTORY_POLICY_ID` — the ID of a Jamf Pro policy with payload Maintenance → Update Inventory. Required when `UPDATE_JAMF_PRO="TRUE"` because user-context can't call `jamf recon` directly; this fires Self Service to run the policy as root.
  - `JSC_STEP_LABEL` — the identifier of your PSSO step. Defaults to `script-psso`.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.

Original `pseudo` is Apache 2.0 (© Kevin M. White). This fork preserves that license; substantial changes are documented in `CHANGELOG.md`.
