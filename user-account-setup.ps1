$ErrorActionPreference = "Stop"

$RequiredLoginUser = "user"
$ManagedAccounts = @(
    [PSCustomObject]@{
        Name = "java"
        Password = "java2026"
    }
    [PSCustomObject]@{
        Name = "dbalgo"
        Password = "dbalgo2026"
    }
)

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

try {
    if (-not (Test-IsAdministrator)) {
        throw "This script must be run as Administrator."
    }

    $currentUser = [Environment]::UserName

    if ($currentUser -ine $RequiredLoginUser) {
        throw "Sign in with the '$RequiredLoginUser' account before running this script. Current account: '$currentUser'."
    }

    $requiredUser = Get-LocalUser -Name $RequiredLoginUser -ErrorAction SilentlyContinue

    if ($null -eq $requiredUser) {
        throw "The required local account '$RequiredLoginUser' does not exist."
    }

    if (-not $requiredUser.Enabled) {
        Enable-LocalUser -Name $RequiredLoginUser
        Write-Host "'$RequiredLoginUser' account enabled."
    }

    $administratorsGroup = Get-LocalGroup -SID "S-1-5-32-544"

    Write-Host "=== Creating or updating managed accounts ==="

    foreach ($account in $ManagedAccounts) {
        $securePassword = ConvertTo-SecureString $account.Password -AsPlainText -Force
        $existingUser = Get-LocalUser -Name $account.Name -ErrorAction SilentlyContinue

        if ($null -eq $existingUser) {
            New-LocalUser `
                -Name $account.Name `
                -Password $securePassword `
                -FullName $account.Name `
                -Description "Managed local account" | Out-Null

            Write-Host "'$($account.Name)' account created."
        }
        else {
            Set-LocalUser -Name $account.Name -Password $securePassword
            Write-Host "'$($account.Name)' account password updated."
        }

        Enable-LocalUser -Name $account.Name
        Write-Host "'$($account.Name)' account enabled."

        $managedUser = Get-LocalUser -Name $account.Name
        $administratorMember = Get-LocalGroupMember -Group $administratorsGroup |
            Where-Object { $_.SID.Value -eq $managedUser.SID.Value }

        if ($null -eq $administratorMember) {
            Add-LocalGroupMember -Group $administratorsGroup -Member $account.Name
            Write-Host "'$($account.Name)' added to the Administrators group."
        }
        else {
            Write-Host "'$($account.Name)' is already in the Administrators group."
        }
    }

    Write-Host "=== Disabling other local accounts ==="

    $protectedAccounts = @($RequiredLoginUser) + @($ManagedAccounts.Name)
    $failedAccounts = @()

    Get-LocalUser | Where-Object { $protectedAccounts -notcontains $_.Name } | ForEach-Object {
        if (-not $_.Enabled) {
            Write-Host "'$($_.Name)' account is already disabled."
            return
        }

        try {
            Disable-LocalUser -Name $_.Name
            Write-Host "'$($_.Name)' account disabled."
        }
        catch {
            $failedAccounts += $_.Name
            Write-Warning "Failed to disable '$($_.Name)': $($_.Exception.Message)"
        }
    }

    if ($failedAccounts.Count -gt 0) {
        throw "Some accounts could not be disabled: $($failedAccounts -join ', ')"
    }

    Write-Host "=== Final local account status ==="
    $administratorSids = @(Get-LocalGroupMember -Group $administratorsGroup | ForEach-Object { $_.SID.Value })

    Get-LocalUser |
        Sort-Object Name |
        Select-Object Name, Enabled, @{
            Name = "Administrator"
            Expression = { $administratorSids -contains $_.SID.Value }
        } |
        Format-Table -AutoSize

    Write-Host "Account setup completed successfully."
}
catch {
    Write-Error "Script failed: $($_.Exception.Message)"
    exit 1
}
