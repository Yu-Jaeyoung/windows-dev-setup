chcp 65001 > $null
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new()
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = "Stop"

$UserName = "input_user_name"
$Password = "input_user_password"

# Wi-Fi settings "NEED INPUT"
$WifiSsid = ""
$WifiPassword = ""   
$WifiProfileName = $WifiSsid

# VS Code direct installer URL (system installer, x64)
$VsCodeInstallerUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
$VsCodeInstallerPath = Join-Path $env:TEMP "VSCodeSetup-x64.exe"

Write-Host "=== Checking administrator privileges ==="

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator."
}

Write-Host "=== Creating user ==="

$userExists = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

if (-not $userExists) {
    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    New-LocalUser `
        -Name $UserName `
        -Password $securePassword `
        -FullName $UserName `
        -Description "Local admin user created by script" `
        -PasswordNeverExpires

    Write-Host "User '$UserName' created successfully"
} else {
    Write-Host "User '$UserName' already exists"
}

Write-Host "=== Assigning administrator role ==="

try {
    Add-LocalGroupMember -Group "Administrators" -Member $UserName -ErrorAction Stop
    Write-Host "Administrator privileges granted"
} catch {
    Write-Host "User is already an administrator or failed to assign"
}

Write-Host "=== Applying system policies ==="

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" -Force | Out-Null
New-ItemProperty `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE" `
    -Name "DisablePrivacyExperience" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
New-ItemProperty `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableWindowsConsumerFeatures" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-ItemProperty `
    -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" `
    -Name "DisableSoftLanding" `
    -PropertyType DWord `
    -Value 1 `
    -Force | Out-Null

New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Force | Out-Null
New-ItemProperty `
    -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" `
    -Name "AllowOnlineTips" `
    -PropertyType DWord `
    -Value 0 `
    -Force | Out-Null

Write-Host "Policies applied"

Write-Host "=== Installing Visual Studio Code ==="

$vsCodeInstalled = $false

if (Get-Command winget -ErrorAction SilentlyContinue) {
    try {
        Write-Host "Trying winget first..."
        winget source update
        winget install --id Microsoft.VisualStudioCode --exact --source winget --scope machine --accept-package-agreements --accept-source-agreements
        $vsCodeInstalled = $true
        Write-Host "VS Code installed via winget"
    } catch {
        Write-Host "winget install failed. Falling back to direct installer."
        try {
            winget source reset --force
            Write-Host "winget sources reset completed"
        } catch {
            Write-Host "winget source reset also failed"
        }
    }
} else {
    Write-Host "winget not found. Using direct installer."
}

if (-not $vsCodeInstalled) {
    Write-Host "Downloading VS Code installer..."
    Invoke-WebRequest -Uri $VsCodeInstallerUrl -OutFile $VsCodeInstallerPath

    Write-Host "Running silent installer..."
    Start-Process -FilePath $VsCodeInstallerPath -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=!runcode" -Wait

    $commonPath = "C:\Program Files\Microsoft VS Code\Code.exe"
    $userPath = Join-Path $env:LOCALAPPDATA "Programs\Microsoft VS Code\Code.exe"

    if ((Test-Path $commonPath) -or (Test-Path $userPath)) {
        $vsCodeInstalled = $true
        Write-Host "VS Code installed via direct installer"
    } else {
        throw "VS Code installation failed"
    }
}

Write-Host "=== Creating Wi-Fi profile ==="

$wifiXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$WifiProfileName</name>
    <SSIDConfig>
        <SSID>
            <name>$WifiSsid</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$WifiPassword</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

$tempDir = Join-Path $env:TEMP "wifi-profile-setup"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$wifiProfilePath = Join-Path $tempDir "wifi-$($WifiSsid).xml"

$wifiXml | Set-Content -Path $wifiProfilePath -Encoding UTF8

netsh wlan add profile filename="$wifiProfilePath" user=all | Out-Host
Write-Host "Wi-Fi profile added"

Write-Host "=== Checking Wi-Fi adapter status ==="

$wifiAdapter = Get-NetAdapter | Where-Object {
    $_.InterfaceDescription -match 'Wireless|Wi-Fi|802.11|WLAN'
} | Select-Object -First 1

if (-not $wifiAdapter) {
    Write-Host "No Wi-Fi adapter detected. Profile was added, but connection was skipped."
} else {
    Write-Host "Detected Wi-Fi adapter: $($wifiAdapter.Name) / Status: $($wifiAdapter.Status)"

    if ($wifiAdapter.Status -ne "Up") {
        try {
            Enable-NetAdapter -Name $wifiAdapter.Name -Confirm:$false -ErrorAction Stop
            Start-Sleep -Seconds 3
            Write-Host "Wi-Fi adapter enabled"
        } catch {
            Write-Host "Could not enable Wi-Fi adapter automatically. Connection attempt skipped."
        }
    }

    $wifiAdapter = Get-NetAdapter -Name $wifiAdapter.Name -ErrorAction SilentlyContinue

    if ($wifiAdapter -and $wifiAdapter.Status -eq "Up") {
        try {
            netsh wlan connect name="$WifiProfileName" ssid="$WifiSsid" | Out-Host
            Write-Host "Wi-Fi connection command sent"
        } catch {
            Write-Host "Wi-Fi connection attempt failed. Check radio state, airplane mode, or password."
        }
    } else {
        Write-Host "Wi-Fi adapter is still not ready. Check airplane mode, hardware wireless switch, or BIOS/driver state."
    }
}

Write-Host "=== Setup completed ==="
Write-Host "User: $UserName"
Write-Host "Wi-Fi SSID: $WifiSsid"
