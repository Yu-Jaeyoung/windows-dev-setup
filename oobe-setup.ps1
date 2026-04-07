# =========================================================
# IMPORTANT: User information must be entered manually
# - Enter account names
# - Enter passwords for each account
# - Password confirmation is required
# =========================================================

# =========================================================
# Windows PowerShell Setup Script
# - Disable OOBE Privacy Experience
# - Bypass Network Requirement (BypassNRO)
# - Create Local Admin Accounts
# =========================================================

$ErrorActionPreference = "Stop"

function Convert-SecureStringToPlainText {
    param (
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Test-ValidLocalUserName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        return $false
    }

    if ($UserName.Length -gt 20) {
        return $false
    }

    if ($UserName -match '[\\\/\[\]:;|=,\+\*\?<>""]') {
        return $false
    }

    return $true
}

try {
    # Ensure script is running with Administrator privileges
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "This script must be run as Administrator."
        exit 1
    }

    # 1. Disable OOBE Privacy Experience
    $registryPathPrivacy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"

    if (-not (Test-Path $registryPathPrivacy)) {
        New-Item -Path $registryPathPrivacy -Force | Out-Null
    }

    New-ItemProperty -Path $registryPathPrivacy `
        -Name "DisablePrivacyExperience" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Host "Privacy experience disabled"

    # 2. Bypass Network Requirement during OOBE
    $registryPathNetwork = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"

    if (-not (Test-Path $registryPathNetwork)) {
        New-Item -Path $registryPathNetwork -Force | Out-Null
    }

    New-ItemProperty -Path $registryPathNetwork `
        -Name "BypassNRO" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Host "Network requirement bypass enabled"

    # Resolve built-in Administrators group
    $adminGroupName = "Administrators"

    # 3. Ask how many users to create
    $userCountInput = Read-Host "Enter the number of local admin accounts to create"

    $parsedUserCount = 0
    if (-not [int]::TryParse($userCountInput, [ref]$parsedUserCount)) {
        throw "Invalid number entered."
    }

    if ($parsedUserCount -le 0) {
        throw "The number of users must be greater than 0."
    }

    # 4. Create users interactively
    for ($i = 1; $i -le $parsedUserCount; $i++) {
        Write-Host ""
        Write-Host "Processing user $i of $parsedUserCount"

        $userName = Read-Host "Enter username"

        if (-not (Test-ValidLocalUserName -UserName $userName)) {
            throw "Invalid username. Use 1-20 characters and avoid invalid symbols."
        }

        $existingUser = Get-LocalUser -Name $userName -ErrorAction SilentlyContinue

        if ($null -eq $existingUser) {
            $passwordConfirmed = $false
            $securePassword = $null

            while (-not $passwordConfirmed) {
                $securePassword1 = Read-Host "Enter password for $userName" -AsSecureString
                $securePassword2 = Read-Host "Confirm password for $userName" -AsSecureString

                $plainPassword1 = Convert-SecureStringToPlainText -SecureString $securePassword1
                $plainPassword2 = Convert-SecureStringToPlainText -SecureString $securePassword2

                if ([string]::IsNullOrWhiteSpace($plainPassword1)) {
                    Write-Host "Password cannot be empty. Please try again."
                    continue
                }

                if ($plainPassword1 -ne $plainPassword2) {
                    Write-Host "Passwords do not match. Please try again."
                    continue
                }

                $securePassword = $securePassword1
                $passwordConfirmed = $true
            }

            New-LocalUser `
                -Name $userName `
                -Password $securePassword `
                -FullName $userName `
                -Description "Automated Account"

            Write-Host "$userName account created"
        }
        else {
            Write-Host "$userName already exists"
        }

        $isMember = Get-LocalGroupMember -Group $adminGroupName -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match "\\$([regex]::Escape($userName))$" }

        if ($null -eq $isMember) {
            Add-LocalGroupMember -Group $adminGroupName -Member $userName
            Write-Host "$userName added to $adminGroupName group"
        }
        else {
            Write-Host "$userName is already in $adminGroupName group"
        }
    }

    Write-Host ""
    Write-Host "All tasks completed successfully."
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
