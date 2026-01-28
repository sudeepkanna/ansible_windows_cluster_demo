#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'SilentlyContinue'

# --------------------------------------------------------------------
# Module specification
# --------------------------------------------------------------------
$spec = @{
  options = @{
    state = @{
      type    = "str"
      choices = @("report", "absent")
      default = "report"
    }

    skipBakKeys = @{
      type    = "bool"
      default = $true
    }

    requireUserSidPrefix = @{
      type    = "bool"
      default = $true
    }

    requireHiveNotLoaded = @{
      type    = "bool"
      default = $true
    }

    requireRefCountZeroIfPresent = @{
      type    = "bool"
      default = $true
    }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# --------------------------------------------------------------------
# Result object
# --------------------------------------------------------------------
$module.Result.changed          = $false
$module.Result.scannedKeyCount  = 0
$module.Result.staleEntries     = @()
$module.Result.removedSids      = @()
$module.Result.warnings         = @()
$module.Result.errors           = @()

# --------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------
$profileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$wellKnownSids   = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

# --------------------------------------------------------------------
# Helper functions (approved verbs only)
# --------------------------------------------------------------------
function Test-UserSidPrefix {
  param([string]$Sid)
  return ($Sid -like 'S-1-5-21-*')
}

function Test-BakKey {
  param([string]$Sid)
  return ($Sid -like '*.bak')
}

function Test-HiveLoaded {
  param([string]$Sid)
  return (Test-Path -LiteralPath ("Registry::HKEY_USERS\$Sid"))
}

# --------------------------------------------------------------------
# Enumerate ProfileList
# --------------------------------------------------------------------
try {
  $profileKeys = Get-ChildItem -LiteralPath $profileListRoot
}
catch {
  $module.FailJson("Failed to enumerate ProfileList registry: $($_.Exception.Message)")
}

foreach ($key in $profileKeys) {

  $module.Result.scannedKeyCount++

  $sid     = $key.PSChildName
  $regPath = $key.PSPath

  # ---------------- Guardrails ----------------

  # Protect system SIDs
  if ($wellKnownSids -contains $sid) { continue }

  # Skip .bak keys by default
  if ($module.Params.skipBakKeys -and (Test-BakKey -Sid $sid)) { continue }

  # Restrict to user SIDs
  if ($module.Params.requireUserSidPrefix -and (-not (Test-UserSidPrefix -Sid $sid))) { continue }

  # Do not touch loaded profiles
  if ($module.Params.requireHiveNotLoaded -and (Test-HiveLoaded -Sid $sid)) { continue }

  # ---------------- Read registry ONCE ----------------
  try {
    $props = Get-ItemProperty -LiteralPath $regPath
  }
  catch {
    $module.Result.warnings += "Unable to read ProfileList key '$regPath' (SID $sid). Skipping."
    continue
  }

  $profileImagePath = $props.ProfileImagePath
  $refCount         = $null

  if ($props.PSObject.Properties.Name -contains 'RefCount') {
    $refCount = $props.RefCount
  }

  # ---------------- Stale detection ----------------

  # ProfileImagePath missing or empty → candidate
  if (-not [string]::IsNullOrWhiteSpace([string]$profileImagePath)) {
    continue
  }

  # RefCount must be zero if present
  if ($module.Params.requireRefCountZeroIfPresent) {
    if ($null -ne $refCount -and [int]$refCount -ne 0) {
      continue
    }
  }

  # ---------------- Record stale entry ----------------
  $module.Result.staleEntries += @{
    sid     = $sid
    regPath = $regPath
    reason  = 'ProfileImagePath missing or empty'
    details = @{
      refCount       = $refCount
      hiveLoaded     = (Test-HiveLoaded -Sid $sid)
      isBakKey       = (Test-BakKey -Sid $sid)
    }
  }
}

# --------------------------------------------------------------------
# Enforcement phase
# --------------------------------------------------------------------
if ($module.Params.state -eq 'absent') {

  foreach ($entry in $module.Result.staleEntries) {

    if ($module.CheckMode) {
      $module.Result.changed = $true
      continue
    }

    try {
      Remove-Item -LiteralPath $entry.regPath -Recurse -Force
      $module.Result.removedSids += $entry.sid
      $module.Result.changed = $true
    }
    catch {
      $module.Result.errors += "Failed to remove $($entry.sid): $($_.Exception.Message)"
    }
  }

  # Fail at end if anything went wrong
  if ($module.Result.errors.Count -gt 0) {
    $module.FailJson("One or more stale ProfileList entries failed to remove. See 'errors' for details.")
  }
}

$module.ExitJson()
