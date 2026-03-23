# Windows Dev Setup Script

This repository provides PowerShell scripts to automate the initial setup of a Windows development environment.

## Overview

The scripts perform the following tasks:

* Create a local user
* Grant administrator privileges
* Disable initial privacy prompts and consumer features
* Install Visual Studio Code
* Configure Wi-Fi profile
* Provide a cleanup script to remove the created user

---

## Scripts

### 1. setup.ps1

Main setup script.

#### Features

* Creates a local user (configurable)
* Adds the user to the `Administrators` group
* Applies system policies:

  * Disable privacy experience
  * Disable Windows consumer features
  * Disable tips and welcome screens
* Installs Visual Studio Code:

  * Uses `winget` if available
  * Falls back to direct installer if necessary
* Configures Wi-Fi:

  * SSID (configurable)
  * Password (configurable)
  * WPA2-PSK / AES support
  * Auto-connect enabled

---

### 2. remove.ps1

Cleanup script.

#### Features

* Removes a specified local user
* Removes the user from all local groups
* Deletes the user's profile directory (optional)

---

## Configuration

Before running the script, update the following variables:

```powershell
$UserName = "your_username"
$Password = "your_password"

$WifiSsid = "your_wifi_ssid"
$WifiPassword = "your_wifi_password"
```

---

## Requirements

* Windows 10 / 11
* Administrator privileges
* Internet connection (required for software installation)
* Wi-Fi adapter enabled (if using wireless configuration)

---

## Usage

### 1. Run PowerShell as Administrator

### 2. Allow script execution (first time only)

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Run setup script

```powershell
.\setup.ps1
```

### 4. Reboot and login with the created user

---

## Wi-Fi Notes

* The script assumes:

  * WPA2-Personal (WPA2-PSK)
  * AES encryption
* Adjust authentication/encryption settings if your network differs

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

---

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

