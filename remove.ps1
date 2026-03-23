# Delete user: 

$UserName = "input_user_name"

Write-Host "=== Checking administrator privileges ==="

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run as Administrator."
}

Write-Host "=== Checking if user exists ==="

$user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

if (-not $user) {
    Write-Host "User '$UserName' does not exist. Nothing to delete."
    exit
}

Write-Host "=== Removing user from groups ==="

$groups = Get-LocalGroup | ForEach-Object {
    try {
        if (Get-LocalGroupMember -Group $_.Name -Member $UserName -ErrorAction Stop) {
            $_.Name
        }
    } catch {}
}

foreach ($group in $groups) {
    try {
        Remove-LocalGroupMember -Group $group -Member $UserName -ErrorAction Stop
        Write-Host "Removed from group: $group"
    } catch {
        Write-Host "Failed to remove from group: $group"
    }
}

Write-Host "=== Deleting user ==="

try {
    Remove-LocalUser -Name $UserName -ErrorAction Stop
    Write-Host "User '$UserName' deleted successfully"
} catch {
    throw "Failed to delete user '$UserName'"
}

Write-Host "=== Cleaning user profile folder (optional) ==="

$profilePath = "C:\Users\$UserName"

if (Test-Path $profilePath) {
    try {
        Remove-Item -Path $profilePath -Recurse -Force -ErrorAction Stop
        Write-Host "User profile folder removed"
    } catch {
        Write-Host "Could not remove profile folder (might be in use)"
    }
} else {
    Write-Host "No profile folder found"
}

Write-Host "=== Done ==="
