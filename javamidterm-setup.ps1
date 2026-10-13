#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules Microsoft.PowerShell.LocalAccounts, NetAdapter

$ErrorActionPreference = "Stop"
$UserName = "javamidterm"
$StatePath = "HKLM:\SOFTWARE\WindowsDevSetup\JavaMidterm"

try {
    # Check recovery accounts before changing anything.
    $restoreNames = @("user", "java", "dbalgo")
    $restoreUsers = @($restoreNames | ForEach-Object { Get-LocalUser -Name $_ })
    $adminGroup = Get-LocalGroup -SID "S-1-5-32-544"
    $adminSids = @(Get-LocalGroupMember -Group $adminGroup | ForEach-Object { $_.SID.Value })
    if (-not ($restoreUsers | Where-Object { $adminSids -contains $_.SID.Value })) {
        throw "At least one of user, java or dbalgo must already be an administrator."
    }

    Write-Host "=== Preparing exam administrator ==="
    $password = ConvertTo-SecureString "261014" -AsPlainText -Force
    $existingUser = Get-LocalUser | Where-Object { $_.Name -eq $UserName }
    if ($null -eq $existingUser) {
        New-LocalUser -Name $UserName -Password $password -FullName $UserName `
            -Description "Java midterm administrator" | Out-Null
    }
    else {
        Set-LocalUser -Name $UserName -Password $password
    }
    Enable-LocalUser -Name $UserName
    $examUser = Get-LocalUser -Name $UserName
    if ($adminSids -notcontains $examUser.SID.Value) {
        Add-LocalGroupMember -Group $adminGroup -Member $examUser
    }

    Write-Host "=== Suppressing initial setup prompts ==="
    $settings = @(
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE"; Name = "DisablePrivacyExperience"; Value = 1 }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE"; Name = "BypassNRO"; Value = 1 }
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsConsumerFeatures"; Value = 1 }
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableSoftLanding"; Value = 1 }
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"; Name = "DisableWindowsSpotlightWindowsWelcomeExperience"; Value = 1 }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Name = "AllowOnlineTips"; Value = 0 }
    )
    foreach ($setting in $settings) {
        Write-Host "Applying: $($setting.Path) / $($setting.Name)"
        if (-not (Test-Path $setting.Path)) {
            New-Item -Path $setting.Path -Force | Out-Null
        }
        New-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value `
            -PropertyType DWord -Force | Out-Null
    }
    Write-Host "BypassNRO requested; support depends on the Windows build."

    Write-Host "=== Disabling physical Wi-Fi adapters ==="
    $wifiAdapters = @(Get-NetAdapter -IncludeHidden | Where-Object {
        $_.HardwareInterface -and -not $_.Virtual -and
        ($_.NdisPhysicalMedium -in @(1, 9) -or $_.InterfaceType -eq 71)
    })
    if ($wifiAdapters.Count -eq 0) {
        throw "No physical Wi-Fi adapter found. Check Network Connections or Device Manager."
    }
    # Write the recovery plan BEFORE disabling anything; keep it across reruns.
    if (-not (Test-Path $StatePath)) {
        New-Item -Path $StatePath -Force | Out-Null
    }
    $state = Get-ItemProperty -Path $StatePath
    $records = @()
    if ($state.AdaptersJson) { $records = @($state.AdaptersJson | ConvertFrom-Json) }
    $devices = @(Get-CimInstance -ClassName Win32_NetworkAdapter)
    foreach ($adapter in $wifiAdapters) {
        if ($adapter.AdminStatus -eq "Down") { continue }
        $guid = ([string]$adapter.InterfaceGuid).Trim('{}')
        $device = $devices | Where-Object { ([string]$_.GUID).Trim('{}') -eq $guid } | Select-Object -First 1
        $pnpId = [string]$adapter.PnPDeviceID
        if (-not $pnpId) { $pnpId = [string]$device.PNPDeviceID }
        if (-not $guid -or -not $pnpId) { throw "Could not record a stable Wi-Fi device identity." }
        if (-not ($records | Where-Object { $_.Guid -eq $guid -or $_.PnpDeviceId -eq $pnpId })) {
            $records += [PSCustomObject]@{ Guid = $guid; PnpDeviceId = $pnpId; Name = $adapter.Name }
        }
    }
    if ($records.Count -gt 0 -or $state.PSObject.Properties.Name -contains "AdaptersJson") {
        New-ItemProperty -Path $StatePath -Name "AdaptersJson" -PropertyType String `
            -Value (ConvertTo-Json -InputObject @($records) -Compress) -Force | Out-Null
    }

    foreach ($adapter in $wifiAdapters) {
        if ($adapter.AdminStatus -ne "Down") {
            Write-Host "Disabling Wi-Fi adapter (interface index): $($adapter.InterfaceIndex)"
            Disable-NetAdapter -Name ([WildcardPattern]::Escape($adapter.Name)) -IncludeHidden -Confirm:$false
        }
        $check = $null
        for ($attempt = 0; $attempt -lt 5; $attempt++) {
            $check = Get-NetAdapter -IncludeHidden | Where-Object { $_.InterfaceGuid -eq $adapter.InterfaceGuid }
            if ($check -and $check.AdminStatus -eq "Down") { break }
            Start-Sleep -Seconds 1
        }
        if (-not $check -or $check.AdminStatus -ne "Down") {
            throw "Wi-Fi adapter could not be disabled (interface index: $($adapter.InterfaceIndex))."
        }
        Write-Host "Wi-Fi adapter disabled (interface index): $($adapter.InterfaceIndex)"
    }

    Write-Host "=== Disabling all other local accounts ==="
    foreach ($account in @(Get-LocalUser | Where-Object { $_.Name -ne $UserName -and $_.Enabled })) {
        Disable-LocalUser -SID $account.SID
        Write-Host "Disabled: $($account.Name)"
    }
    $enabledUsers = @(Get-LocalUser | Where-Object { $_.Enabled })
    if ($enabledUsers.Count -ne 1 -or $enabledUsers[0].Name -ne $UserName) {
        throw "Account verification failed."
    }
    Get-LocalUser | Sort-Object Name | Select-Object Name, Enabled | Format-Table -AutoSize
    Write-Host "Setup completed. Sign out of other sessions and sign in as .\javamidterm."
    Write-Host "Run the restore script from C:\Users\user\Desktop using an elevated PowerShell."
}
catch {
    Write-Host "Setup failed; some changes may already be applied." -ForegroundColor Red
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host "Command: $($_.InvocationInfo.MyCommand.Name)"
    Write-Host "Error type: $($_.Exception.GetType().FullName)"
    Write-Host "HResult: $($_.Exception.HResult)"
    if ($_.Exception.Message -notmatch '[^\x00-\x7F]') {
        Write-Host "Details: $($_.Exception.Message)"
    }
    exit 1
}
