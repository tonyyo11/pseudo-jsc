# CHANGELOG

## [Unreleased]

### Added
- SmartCard / PIV authentication support in `HelperScripts/pseudo-jsc.sh`:
  - Pre-registration `security list-smartcards` polling loop with configurable timeout, waiting for the user to insert their SmartCard before opening Platform SSO registration.
  - `check_psso_smartcard_auth_status()` to detect the `coreautha` SmartCard pairing window during registration.
  - Post-registration pairing wait loop that holds the workflow open until both the `coreautha` window closes and the registration window returns `CLOSE`.
  - `coreautha` added to the `focus_psso_registration` don't-hide list so the SmartCard PIN prompt remains visible during pairing.
  - `smartCardTokenId` captured in `check_psso_user_status` for logging.

### Changed
- Forked from [sebLuns/SetupChecklistAssets](https://github.com/sebLuns/SetupChecklistAssets) at commit `53a0365`. Renamed `HelperScripts/JSCeudo_PSSO.sh` to `HelperScripts/pseudo-jsc.sh`. Updated `ScriptSteps/script-psso` `buttonScript` to invoke the new script name and the deployment path `/Library/Application Support/SetupChecklistHelpers/pseudo-jsc.sh`.
- Apache License 2.0 file added (inherited from upstream `pseudo`); fork preserves the same license.
- Added `# shellcheck disable=SC1003,SC2012,SC2024,SC2207` directive at the top of `pseudo-jsc.sh`, matching the upstream `pseudo` convention. Brings the lint output clean.
- Loosened `psso_user_status_state` match in `check_psso_user_status` from exact `"POUserStateNormal (0)"` to any value containing `Normal`, to absorb future Apple format variations.
- Applied `tr -d '\\'` to `app-sso platform -s` output before `jq` parses it — fixes a known escape-character bug present in newer macOS.

### Fixed
- `ScriptSteps/welcome-message` previously referenced `clearNotifs.sh`, which does not exist in the repo. Updated to `clearNotifications.sh`.
- `ScriptSteps/script-chrome-login` previously referenced `/path/to/clearNotifications.sh`. Updated to the documented deployment path `/Library/Application Support/SetupChecklistHelpers/clearNotifications.sh`.
- Post-registration loop in `workflow_psso` previously called the non-existent `check_psso_registration_active`, which caused an infinite background loop after the user successfully registered. Replaced with the new SmartCard pairing wait (when applicable) plus bounded outer loop.

### Removed
- Unused config constant `JAMF_PRO_BINARY` (never referenced — JSC user-context can't shell out to `/usr/local/bin/jamf` directly; the `jamfselfservice://` URL is the actual mechanism).
- Unused function `hide_all_apps()` (defined but never called by any code path).

## Post-0.1.0 work

### Fixed
- `main()` now checks the return code from `workflow_psso` and skips post-PSSO actions (`jamf_pro_update_inventory`, `jamf_pro_manual_comliance_registration`) when the workflow did not complete successfully. Previously the inventory Self Service policy fired after a PSSO timeout or missing-SmartCard failure, producing misleading downstream reporting.

### Upstream sources at fork time
- [Macjutsu/pseudo](https://github.com/Macjutsu/pseudo) 1.0.0-beta5, commit `2d942ca`. Source for the SmartCard logic.
- [sebLuns/SetupChecklistAssets](https://github.com/sebLuns/SetupChecklistAssets), commit `53a0365`. Source for the user-context JSC adaptation and the surrounding repo layout.
