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
