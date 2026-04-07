param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Setup", "Restore")]
    [string]$Mode
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

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

function Read-NonEmptyInput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }

        Write-Host "Input cannot be empty."
    }
}

function Read-OptionalCsvInput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    $raw = Read-Host $Prompt

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    return $raw.Split(",") |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" } |
        Select-Object -Unique
}

function Read-YesNo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    while ($true) {
        $answer = (Read-Host "$Message (Y/N)").Trim().ToUpperInvariant()

        switch ($answer) {
            "Y" { return $true }
            "N" { return $false }
            default { Write-Host "Please enter Y or N." }
        }
    }
}

function Read-ConfirmedPassword {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetName
    )

    while ($true) {
        $password1 = Read-Host "Enter password for $TargetName" -AsSecureString
        $password2 = Read-Host "Confirm password for $TargetName" -AsSecureString

        $plain1 = Convert-SecureStringToPlainText -SecureString $password1
        $plain2 = Convert-SecureStringToPlainText -SecureString $password2

        if ([string]::IsNullOrWhiteSpace($plain1)) {
            Write-Host "Password cannot be empty. Please try again."
            continue
        }

        if ($plain1 -ne $plain2) {
            Write-Host "Passwords do not match. Please try again."
            continue
        }

        return $password1
    }
}

function Ensure-LocalUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$Password,
        [string]$Description = "Managed Account"
    )

    $existingUser = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

    if ($null -eq $existingUser) {
        New-LocalUser `
            -Name $UserName `
            -Password $Password `
            -FullName $UserName `
            -Description $Description | Out-Null

        Write-Host "$UserName account created."
    }
    else {
        Write-Host "$UserName account already exists."
    }

    Enable-LocalUser -Name $UserName
    Write-Host "$UserName account enabled."
}

function Disable-LocalUserIfExists {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

    if ($null -ne $user) {
        Disable-LocalUser -Name $UserName
        Write-Host "$UserName account disabled."
    }
    else {
        Write-Host "$UserName account does not exist. Skipped."
    }
}

function Enable-LocalUserIfExists {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

    if ($null -ne $user) {
        Enable-LocalUser -Name $UserName
        Write-Host "$UserName account enabled."
    }
    else {
        Write-Host "$UserName account does not exist. Skipped."
    }
}

function Add-ToAdministratorsIfNeeded {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $groupName = "Administrators"

    $member = Get-LocalGroupMember -Group $groupName -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "\\$([regex]::Escape($UserName))$" }

    if ($null -eq $member) {
        Add-LocalGroupMember -Group $groupName -Member $UserName
        Write-Host "$UserName added to $groupName group."
    }
    else {
        Write-Host "$UserName is already in $groupName group."
    }
}

function Add-DenyAllWifiFilter {
    netsh wlan add filter permission=denyall networktype=infrastructure | Out-Null
    Write-Host "Wi-Fi deny-all filter added."
}

function Remove-DenyAllWifiFilter {
    netsh wlan delete filter permission=denyall networktype=infrastructure | Out-Null
    Write-Host "Wi-Fi deny-all filter removed."
}

function Add-AllowWifiFilter {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Ssid
    )

    netsh wlan add filter permission=allow ssid="$Ssid" networktype=infrastructure | Out-Null
    Write-Host "Allowed SSID added: $Ssid"
}

function Remove-AllowWifiFilter {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Ssid
    )

    netsh wlan delete filter permission=allow ssid="$Ssid" networktype=infrastructure | Out-Null
    Write-Host "Allowed SSID removed: $Ssid"
}

try {
    if (-not (Test-IsAdministrator)) {
        throw "This script must be run as Administrator."
    }

    switch ($Mode) {
        "Setup" {
            Write-Host "Setup mode started."

            $accountCountInput = Read-NonEmptyInput -Prompt "Enter the number of managed accounts to create"
            $parsedCount = 0

            if (-not [int]::TryParse($accountCountInput, [ref]$parsedCount)) {
                throw "Invalid number entered."
            }

            if ($parsedCount -le 0) {
                throw "The number of accounts must be greater than 0."
            }

            $managedAccounts = @()

            for ($i = 1; $i -le $parsedCount; $i++) {
                Write-Host ""
                Write-Host "Configuring managed account $i of $parsedCount"

                while ($true) {
                    $userName = Read-NonEmptyInput -Prompt "Enter account name"

                    if (-not (Test-ValidLocalUserName -UserName $userName)) {
                        Write-Host "Invalid username. Use 1-20 characters and avoid invalid symbols."
                        continue
                    }

                    $alreadyAdded = $managedAccounts | Where-Object { $_ -eq $userName }
                    if ($null -ne $alreadyAdded) {
                        Write-Host "This account name is already entered. Please use a different name."
                        continue
                    }

                    break
                }

                $securePassword = Read-ConfirmedPassword -TargetName $userName

                Ensure-LocalUser -UserName $userName -Password $securePassword -Description "Managed Account"
                Add-ToAdministratorsIfNeeded -UserName $userName

                $managedAccounts += $userName
            }

            $excludedAccounts = Read-OptionalCsvInput -Prompt "Enter account names to keep enabled (comma-separated, leave blank if none)"
            $accountsToDisable = Read-OptionalCsvInput -Prompt "Enter account names to disable (comma-separated, leave blank if none)"

            $currentUser = $env:USERNAME

            foreach ($accountName in $accountsToDisable) {
                if ($managedAccounts -contains $accountName) {
                    Write-Host "$accountName is a managed account and will not be disabled. Skipped."
                    continue
                }

                if ($excludedAccounts -contains $accountName) {
                    Write-Host "$accountName is in the keep-enabled list. Skipped."
                    continue
                }

                if ($accountName -eq $currentUser) {
                    Write-Host "$accountName is the current session user and will not be disabled. Skipped."
                    continue
                }

                Disable-LocalUserIfExists -UserName $accountName
            }

            $useWifiRestriction = Read-YesNo -Message "Do you want to enable Wi-Fi restriction"

            if ($useWifiRestriction) {
                Add-DenyAllWifiFilter

                $allowSpecificSsids = Read-YesNo -Message "Do you want to allow specific SSIDs"

                if ($allowSpecificSsids) {
                    $allowedSsids = Read-OptionalCsvInput -Prompt "Enter allowed SSIDs (comma-separated, leave blank to block all Wi-Fi)"

                    foreach ($ssid in $allowedSsids) {
                        Add-AllowWifiFilter -Ssid $ssid
                    }
                }
            }

            Write-Host "Setup mode completed successfully."
        }

        "Restore" {
            Write-Host "Restore mode started."

            $managedAccounts = Read-OptionalCsvInput -Prompt "Enter managed account names to disable (comma-separated, leave blank if none)"
            $accountsToEnable = Read-OptionalCsvInput -Prompt "Enter account names to re-enable (comma-separated, leave blank if none)"

            foreach ($accountName in $managedAccounts) {
                Disable-LocalUserIfExists -UserName $accountName
            }

            foreach ($accountName in $accountsToEnable) {
                Enable-LocalUserIfExists -UserName $accountName
            }

            $removeWifiRestriction = Read-YesNo -Message "Do you want to remove Wi-Fi restriction"

            if ($removeWifiRestriction) {
                $removeAllowedSsids = Read-YesNo -Message "Were specific SSIDs allowed during setup"

                if ($removeAllowedSsids) {
                    $allowedSsids = Read-OptionalCsvInput -Prompt "Enter allowed SSIDs to remove (comma-separated, leave blank if none)"

                    foreach ($ssid in $allowedSsids) {
                        Remove-AllowWifiFilter -Ssid $ssid
                    }
                }

                Remove-DenyAllWifiFilter
            }

            Write-Host "Restore mode completed successfully."
        }
    }
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
