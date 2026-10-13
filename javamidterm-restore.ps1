#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules Microsoft.PowerShell.LocalAccounts, NetAdapter, PnpDevice

$ErrorActionPreference = "Stop"
$RestoreNames = @("user", "java", "dbalgo")
$StatePath = "HKLM:\SOFTWARE\WindowsDevSetup\JavaMidterm"

function Remove-DenyAllWifiFilter {
    netsh wlan delete filter permission=denyall networktype=infrastructure 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Wi-Fi filter removal was not confirmed (netsh exit code: $LASTEXITCODE). The filter may already be absent." -ForegroundColor Yellow
        return $false
    }
    Write-Host "Wi-Fi deny-all filter removed."
    return $true
}

try {
    # Resolve every account before making changes. Do not create missing accounts.
    $restoreUsers = @($RestoreNames | ForEach-Object { Get-LocalUser -Name $_ })
    $adminGroup = Get-LocalGroup -SID "S-1-5-32-544"
    $adminSids = @(Get-LocalGroupMember -Group $adminGroup | ForEach-Object { $_.SID.Value })
    if (-not ($restoreUsers | Where-Object { $adminSids -contains $_.SID.Value })) {
        throw "At least one recovery account must be an administrator."
    }

    Write-Host "=== Enabling recovery accounts ==="
    foreach ($account in $restoreUsers) {
        Enable-LocalUser -SID $account.SID
        Write-Host "Enabled: $($account.Name)"
    }
    foreach ($name in $RestoreNames) {
        if (-not (Get-LocalUser -Name $name).Enabled) { throw "Could not enable '$name'." }
    }

    Write-Host "=== Recovering Wi-Fi devices ==="
    $state = $null
    if (Test-Path $StatePath) { $state = Get-ItemProperty -Path $StatePath }
    $hasSavedPlan = $null -ne $state -and $state.PSObject.Properties.Name -contains "AdaptersJson"
    $records = @()
    if ($hasSavedPlan) { $records = @($state.AdaptersJson | ConvertFrom-Json) }
    # Support the GUID-only record written by the first setup version.
    foreach ($oldGuid in @($state.WifiAdapterGuids | Where-Object { $_ })) {
        $guid = ([string]$oldGuid).Trim('{}')
        if (-not ($records | Where-Object { $_.Guid -eq $guid })) {
            $records += [PSCustomObject]@{ Guid = $guid; PnpDeviceId = ""; Legacy = $true }
        }
    }

    if (-not $hasSavedPlan) {
        Write-Host "No current recovery plan found. Discovering legacy Wi-Fi devices."
        $netAdapters = @(Get-NetAdapter -IncludeHidden)
        $devices = @(Get-CimInstance -ClassName Win32_NetworkAdapter)
        $pnpDevices = @(Get-PnpDevice -Class Net -PresentOnly)
        # The legacy versions did not always save identities. Identify physical
        # wireless devices from NDIS metadata, WMI, or their PnP device name.
        $wirelessPattern = 'Wi-?Fi|Wireless|WLAN|802\.11'
        $wirelessNet = @($netAdapters | Where-Object {
            $_.HardwareInterface -and -not $_.Virtual -and
            ($_.NdisPhysicalMedium -in @(1, 9) -or $_.InterfaceType -eq 71)
        })
        $candidates = @($devices | Where-Object {
            ($_.PhysicalAdapter -or $_.PNPDeviceID -match '^(PCI|USB|SD)\\') -and
            ($_.AdapterTypeID -eq 9 -or $_.Name -match $wirelessPattern) -and
            $_.Name -notmatch 'Virtual|Wi-Fi Direct'
        })
        # Join by GUID explicitly; do not rely on disabled adapters retaining media metadata.
        foreach ($device in $devices) {
            if ($wirelessNet | Where-Object { ([string]$_.InterfaceGuid).Trim('{}') -eq ([string]$device.GUID).Trim('{}') }) {
                if ($candidates -notcontains $device) { $candidates += $device }
            }
        }
        foreach ($device in $candidates) {
            $guid = ([string]$device.GUID).Trim('{}')
            $pnpId = [string]$device.PNPDeviceID
            $existingRecord = $records | Where-Object { ($guid -and $_.Guid -eq $guid) -or ($pnpId -and $_.PnpDeviceId -eq $pnpId) } | Select-Object -First 1
            if ($existingRecord) {
                if (-not $existingRecord.PnpDeviceId) { $existingRecord.PnpDeviceId = $pnpId }
            }
            else {
                $records += [PSCustomObject]@{ Guid = $guid; PnpDeviceId = $pnpId; Legacy = $true }
            }
        }
        foreach ($device in $pnpDevices | Where-Object {
            $_.InstanceId -match '^(PCI|USB|SD)\\' -and $_.FriendlyName -match $wirelessPattern
        }) {
            if (-not ($records | Where-Object { $_.PnpDeviceId -eq $device.InstanceId })) {
                $records += [PSCustomObject]@{ Guid = ""; PnpDeviceId = $device.InstanceId; Legacy = $true }
            }
        }
        if ($records.Count -eq 0) {
            throw "No saved or identifiable wireless device found. Device/driver inspection is required; recovery was not confirmed."
        }
    }

    # Persist discovered legacy identities as well, so a failed recovery can be retried.
    if (-not (Test-Path $StatePath)) { New-Item -Path $StatePath -Force | Out-Null }
    New-ItemProperty -Path $StatePath -Name "AdaptersJson" -PropertyType String `
        -Value (ConvertTo-Json -InputObject @($records) -Compress) -Force | Out-Null
    if ($state -and $state.PSObject.Properties.Name -contains "WifiAdapterGuids") {
        Remove-ItemProperty -Path $StatePath -Name "WifiAdapterGuids"
    }
    $pending = @()
    foreach ($record in $records) {
        try {
            $device = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {
                ($record.PnpDeviceId -and $_.PNPDeviceID -eq $record.PnpDeviceId) -or
                ($record.Guid -and ([string]$_.GUID).Trim('{}') -eq $record.Guid)
            } | Select-Object -First 1
            $net = Get-NetAdapter -IncludeHidden | Where-Object {
                ($record.Guid -and ([string]$_.InterfaceGuid).Trim('{}') -eq $record.Guid) -or
                ($record.PnpDeviceId -and $_.PnPDeviceID -eq $record.PnpDeviceId)
            } | Select-Object -First 1
            if ($record.Legacy -and (($net -and $net.Virtual) -or
                ($device -and -not $device.PhysicalAdapter -and $device.PNPDeviceID -match '^(ROOT|SWD)\\'))) {
                Write-Host "Skipped a virtual device from the legacy recovery record."
                continue
            }
            $pnpId = $record.PnpDeviceId
            if (-not $pnpId -and $device) { $pnpId = $device.PNPDeviceID }
            if ($pnpId) {
                $problem = Get-PnpDeviceProperty -InstanceId $pnpId -KeyName 'DEVPKEY_Device_ProblemCode'
                if ($problem.Data -eq 22) {
                    Enable-PnpDevice -InstanceId $pnpId -Confirm:$false | Out-Null
                }
            }
            # WMI can still expose a disabled device omitted by Get-NetAdapter.
            if ($device -and -not ($device.NetEnabled -eq $true -and $device.ConfigManagerErrorCode -eq 0)) {
                $result = Invoke-CimMethod -InputObject $device -MethodName Enable
                if ($result.ReturnValue -ne 0) { throw "Device enable returned code $($result.ReturnValue)." }
            }
            elseif (-not $device -and $net) {
                Enable-NetAdapter -Name ([WildcardPattern]::Escape($net.Name)) -IncludeHidden -Confirm:$false
            }
            elseif (-not $device -and -not $pnpId) { throw "Saved device is missing." }

            $enabled = $false
            for ($attempt = 0; $attempt -lt 10; $attempt++) {
                $check = Get-CimInstance -ClassName Win32_NetworkAdapter | Where-Object {
                    ($pnpId -and $_.PNPDeviceID -eq $pnpId) -or
                    ($record.Guid -and ([string]$_.GUID).Trim('{}') -eq $record.Guid)
                }
                $netCheck = Get-NetAdapter -IncludeHidden | Where-Object {
                    ($pnpId -and $_.PnPDeviceID -eq $pnpId) -or
                    ($record.Guid -and ([string]$_.InterfaceGuid).Trim('{}') -eq $record.Guid)
                }
                if (($check | Where-Object { $_.NetEnabled -eq $true -and $_.ConfigManagerErrorCode -eq 0 }) -or
                    ($netCheck | Where-Object { $_.InterfaceAdminStatus -eq 1 -or $_.AdminStatus -eq "Up" })) {
                    $enabled = $true
                    break
                }
                Start-Sleep -Seconds 1
            }
            if (-not $enabled) { throw "Device did not reach the enabled state." }
            Write-Host "Wi-Fi device enabled and verified."
        }
        catch {
            $pending += $record
            Write-Host "Warning: Wi-Fi recovery is unresolved for GUID: $($record.Guid); PnP ID: $($record.PnpDeviceId)" -ForegroundColor Yellow
            Write-Host "Error type: $($_.Exception.GetType().FullName); HResult: $($_.Exception.HResult)"
            if ($_.Exception.Message -notmatch '[^\x00-\x7F]') { Write-Host "Details: $($_.Exception.Message)" }
        }
    }
    New-ItemProperty -Path $StatePath -Name "AdaptersJson" -PropertyType String `
        -Value (ConvertTo-Json -InputObject @($pending) -Compress) -Force | Out-Null
    if ($pending.Count -gt 0) {
        Write-Host "Warning: $($pending.Count) device record(s) remain unresolved and were retained. Continuing account recovery." -ForegroundColor Yellow
    }
    # Compatibility cleanup for the earlier filter-based setup only.
    Write-Host "=== Removing legacy Wi-Fi filter, if present ==="
    $filterRemoved = Remove-DenyAllWifiFilter

    Write-Host "=== Disabling accounts outside the recovery list ==="
    foreach ($account in @(Get-LocalUser | Where-Object { $_.Name -notin $RestoreNames -and $_.Enabled })) {
        Disable-LocalUser -SID $account.SID
        Write-Host "Disabled: $($account.Name)"
    }
    $enabledUsers = @(Get-LocalUser | Where-Object { $_.Enabled })
    if ($enabledUsers.Count -ne 3 -or @($enabledUsers | Where-Object { $_.Name -notin $RestoreNames }).Count -gt 0) {
        throw "Account verification failed."
    }
    Get-LocalUser | Sort-Object Name | Select-Object Name, Enabled | Format-Table -AutoSize
    Write-Host "Account recovery completed. Sign out and sign in as user, java or dbalgo."
    Write-Host "Initial setup suppression policies remain applied."
    if (-not $filterRemoved) {
        Write-Host "Wi-Fi adapters were processed, but filter removal was not confirmed. Check WLAN filters before assuming network recovery is complete." -ForegroundColor Yellow
    }
    if ($pending.Count -gt 0 -or -not $filterRemoved) {
        Write-Host "Account recovery completed with network warnings. Unresolved device records do not prevent account recovery." -ForegroundColor Yellow
    }
    else {
        Write-Host "Restore completed. No pending device recovery records remain."
    }
}
catch {
    Write-Host "Restore failed; some changes may already be applied." -ForegroundColor Red
    Write-Host "Line: $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host "Command: $($_.InvocationInfo.MyCommand.Name)"
    Write-Host "Error type: $($_.Exception.GetType().FullName)"
    Write-Host "HResult: $($_.Exception.HResult)"
    if ($_.Exception.Message -notmatch '[^\x00-\x7F]') {
        Write-Host "Details: $($_.Exception.Message)"
    }
    exit 1
}
