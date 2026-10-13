# Windows Dev Setup Scripts

PowerShell scripts for automating Windows initial setup and development environment configuration.

---

## How to Run a PowerShell Script

This script must be executed with administrative privileges.

### 1. Open PowerShell as Administrator

* Press `Start`
* Search for **PowerShell**
* Right-click → **Run as Administrator**

---

### 2. Execute the Script

Run the following command:

```powershell
powershell -ExecutionPolicy Bypass -File "<PATH_TO_SCRIPT>\<SCRIPT_NAME>.ps1"
```

### Example

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\script.ps1"
```

---

### Notes

* `-ExecutionPolicy Bypass` allows the script to run without permanently changing system policy
* Replace `<PATH_TO_SCRIPT>` with the actual directory path
* Replace `<SCRIPT_NAME>.ps1` with your script file name
* The script will fail if not executed with Administrator privileges

---

## Scripts

### 1. `oobe-setup.ps1` - OOBE Initial Setup

Use this script **during or right after Windows OOBE (Out-Of-Box Experience)** to prepare the system for first use.

* Disables OOBE Privacy Experience (registry policy)
* Bypasses Network Requirement during OOBE (BypassNRO)
* Creates local admin accounts interactively (username / password with confirmation)
* Supports creating multiple accounts at once

---

### 2. `dev-setup.ps1` - Development Environment Setup

Use this script **after Windows is fully set up** to configure the development environment.

* Creates a local user (hardcoded in script)
* Grants administrator privileges
* Applies system policies:
  * Disable privacy experience
  * Disable Windows consumer features
  * Disable tips and welcome screens
* Installs Visual Studio Code:
  * Uses `winget` if available
  * Falls back to direct installer if necessary
* Configures Wi-Fi:
  * WPA2-PSK / AES
  * Auto-connect enabled

> Before running, update the variables at the top of the script:
>
> ```powershell
> $UserName = "your_username"
> $Password = "your_password"
> $WifiSsid = "your_wifi_ssid"
> $WifiPassword = "your_wifi_password"
> ```

---

### 3. `exam-lockdown.ps1` - Exam Lockdown

Use this script to **temporarily lock down a PC for exams or assessments**. Operates in two modes via the `-Mode` parameter.

#### Setup mode (`-Mode Setup`)

* Creates managed local admin accounts interactively
* Disables specified existing accounts (protects managed accounts, keep-enabled list, and current session user)
* Restricts Wi-Fi: deny-all filter + optional SSID whitelist

#### Restore mode (`-Mode Restore`)

* Disables managed accounts created during setup
* Re-enables previously disabled accounts
* Removes Wi-Fi restrictions (allowed SSIDs + deny-all filter)

```powershell
# Lock down
powershell -ExecutionPolicy Bypass -File "exam-lockdown.ps1" -Mode Setup

# Restore
powershell -ExecutionPolicy Bypass -File "exam-lockdown.ps1" -Mode Restore
```

---

### 4. `remove-user.ps1` - User Cleanup

Use this script to **remove a local user account** created by the setup scripts.

* Removes the user from all local groups
* Deletes the local user account
* Removes the user's profile directory (optional)

> Before running, update the variable at the top of the script:
>
> ```powershell
> $UserName = "target_username"
> ```

---

### 5. `user-account-setup.ps1` - Managed User Account Setup

Run this script while signed in with the local `user` account.

* Keeps the `user` account enabled
* Creates and enables the following local administrator accounts:
  * `java` / `java2026`
  * `dbalgo` / `dbalgo2026`
* Updates the password and re-enables either managed account if it already exists
* Disables every other local account without deleting it

```powershell
powershell -ExecutionPolicy Bypass -File "user-account-setup.ps1"
```

---

### 6. Java Midterm Setup and Restore

Copy both `javamidterm-setup.ps1` and `javamidterm-restore.ps1` to the `user` account's
Desktop (`C:\Users\user\Desktop`), following the existing script execution pattern.
Run from a local console using
64-bit Windows PowerShell as Administrator, not over a Wi-Fi remote session.
The existing `user`, `java` and `dbalgo` accounts must exist, and at least one
must already be an administrator. No software is installed.

```powershell
# Before the exam, signed in as user, as Administrator:
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\user\Desktop\javamidterm-setup.ps1"

# After the exam, from javamidterm, as Administrator:
powershell.exe -ExecutionPolicy Bypass -File "C:\Users\user\Desktop\javamidterm-restore.ps1"
```

The commands work from `C:\Windows\System32`; changing directories is unnecessary.
The restore command intentionally refers to the original `user` Desktop, not the
`javamidterm` Desktop. If its permissions prevent access, copy the restore file to
the `javamidterm` Desktop and use that file's full path.

Setup:

* Creates or updates `javamidterm` with password `261014`, enables it, and grants administrator rights.
* Applies the existing privacy, consumer-feature and tips suppression settings, plus welcome-experience suppression.
* Sets `BypassNRO=1`, as in `oobe-setup.ps1`. Windows build/edition and organization policies can limit these settings; this is not a guarantee that every OOBE or first-login screen will be skipped. Normal first-login profile creation still occurs.
* Records the GUID, PnP device ID and name of each enabled physical Wi-Fi adapter in `HKLM:\SOFTWARE\WindowsDevSetup\JavaMidterm` (`AdaptersJson`) BEFORE disabling it. Repeated setup preserves outstanding recovery records. Adapter discovery includes hidden interfaces but excludes virtual interfaces. Wired Ethernet is unchanged; no WLAN filter is added.
* Disables every other local account, including the account running the script, only after the preceding steps succeed.

Restore:

* Enables only `user`, `java` and `dbalgo`, preserving their passwords and group memberships.
* Restores devices by saved GUID/PnP identity, not by reclassifying a disabled device as Wi-Fi. It uses PnP to enable disabled hardware when needed and WMI/NetAdapter to enable and verify the interface. Only verified records are cleared; failures remain recorded for retry. Other devices are still attempted if one recovery fails.
* Supports the original `WifiAdapterGuids` record. For old PCs without a current recovery plan, it discovers physical wireless devices using hidden NDIS interfaces, WMI wireless metadata/device names and present PCI/USB/SD wireless PnP devices. This fallback may also enable a wireless device that was disabled before setup, since the old scripts did not record its original state. No setup rerun is required. Unidentifiable or missing devices are reported, not treated as successfully recovered.
* Attempts to remove the legacy deny-all WLAN filter left by the earlier filter-based setup. This is compatibility cleanup; the current setup does not add that filter. An absent filter may produce a warning.
* After enabling and verifying the recovery accounts, attempts network recovery and disables all other local accounts, including `javamidterm`. Unresolved device records produce warnings and do not prevent account cleanup. Accounts and profiles are not deleted.
* Keeps initial setup suppression policies applied.

Disabling an account does not terminate its existing session. Sign out of other
sessions before the exam and sign out of `javamidterm` after restoring.
Administrator users can undo the Wi-Fi/account restrictions. Setup stops if no
physical Wi-Fi adapter is found. Restore retains unresolved device records for retry
and reports network warnings while completing account recovery. Account validation
failures and failures outside individual device recovery still stop the script.
Disabling an adapter may hide the Wi-Fi page in Windows Settings until it is enabled
again. Restore enables the adapters before attempting legacy filter cleanup; failure
of that cleanup is reported as unconfirmed without preventing account recovery.
Localized `netsh` output is suppressed; script failures
use English labels with the line number, command, error type and HResult. ASCII-only
exception details are also displayed. PowerShell startup errors (such as failed
`#Requires` checks) are generated before the script runs and may still be localized.
If the password `261014` is rejected
by password policy, setup stops before disabling Wi-Fi or other accounts and does
not weaken that policy. Failures may leave partial changes; resolve the reported
error and rerun setup or restore. Neither script automatically signs out or restarts.

Removing a WLAN filter alone does not re-enable a disabled adapter, so restore
performs both operations. An enabled adapter is not proof of an Internet connection;
an available network, valid credentials and an enabled hardware radio are still needed.

---

## Requirements

* Windows 10 / 11
* Administrator privileges
* Internet connection (required for software installation in `dev-setup.ps1`)
* Wi-Fi adapter enabled (if using wireless configuration)

---

## Troubleshooting

### VS Code installation fails

* Ensure network connectivity
* Try:

```powershell
winget source update
winget source reset --force
```

* If `winget` is not working, the script will attempt a direct installer

### Wi-Fi connection fails

* Check:
  * Airplane mode is OFF
  * Wi-Fi adapter is enabled
  * Correct credentials are provided

Verify connection status:

```powershell
netsh wlan show interfaces
```

---

## Security Notice

* Do not use weak or default passwords in production environments
* Always replace placeholder credentials before execution

---

## License

MIT License
