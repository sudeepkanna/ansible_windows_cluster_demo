#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'SilentlyContinue'

# --------------------------------------------------------------------
# Module specification
# --------------------------------------------------------------------
$spec = @{
  options = @{
    state = @{ type = "str"; choices = @("report","absent"); default = "report" }

    # Guardrails
    skipBakKeys = @{ type = "bool"; default = $true }
    requireUserSidPrefix = @{ type = "bool"; default = $true }
    requireHiveNotLoaded = @{ type = "bool"; default = $true }
    requireRefCountZeroIfPresent = @{ type = "bool"; default = $true }

    # Diagnostics (safe: stored in result, not printed)
    includeSkipReasons = @{ type = "bool"; default = $true }
    maxSkipReasons = @{ type = "int"; default = 50 }   # prevents giant payloads
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
$module.Result.skipReasons      = @()   # [{sid, regPath, reason}]
$module.Result.matchedCount     = 0

# --------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------
$profileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$wellKnownSids   = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

# --------------------------------------------------------------------
# Helpers (approved verbs only)
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

function Add-SkipReason {
  param(
    [string]$Sid,
    [string]$RegPath,
    [string]$Reason,
    [int]$Max
  )
  if (-not $module.Params.includeSkipReasons) { return }
  if ($module.Result.skipReasons.Count -ge $Max) { return }
  $module.Result.skipReasons += @{ sid = $Sid; regPath = $RegPath; reason = $Reason }
}

# --------------------------------------------------------------------
# Enumerate ProfileList keys
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

  # Guardrail: protect system SIDs
  if ($wellKnownSids -contains $sid) {
    Add-SkipReason -Sid $sid -RegPath $regPath -Reason "Skipped well-known system SID" -Max $module.Params.maxSkipReasons
    continue
  }

  # Guardrail: skip .bak keys by default
  if ($module.Params.skipBakKeys -and (Test-BakKey -Sid $sid)) {
    Add-SkipReason -Sid $sid -RegPath $regPath -Reason "Skipped .bak key" -Max $module.Params.maxSkipReasons
    continue
  }

  # Guardrail: restrict to S-1-5-21-* if enabled
  if ($module.Params.requireUserSidPrefix -and (-not (Test-UserSidPrefix -Sid $sid))) {
    Add-SkipReason -Sid $sid -RegPath $regPath -Reason "SID not in S-1-5-21-* scope" -Max $module.Params.maxSkipReasons
    continue
  }

  # Guardrail: do not touch loaded hives
  if ($module.Params.requireHiveNotLoaded -and (Test-HiveLoaded -Sid $sid)) {
    Add-SkipReason -Sid $sid -RegPath $regPath -Reason "Hive is loaded under HKEY_USERS" -Max $module.Params.maxSkipReasons
    continue
  }

  # Read registry once
  $props = $null
  try {
    $props = Get-ItemProperty -LiteralPath $regPath
  }
  catch {
    $module.Result.warnings += "Unable to read ProfileList key '$regPath' (SID $sid). Skipping."
    continue
  }

  # Detect ProfileImagePath state precisely:
  # - property missing entirely
  # - property present but empty/whitespace
  $hasProfileImagePathProperty = ($props.PSObject.Properties.Name -contains 'ProfileImagePath')
  $profileImagePath = $null
  if ($hasProfileImagePathProperty) {
    $profileImagePath = $props.ProfileImagePath
  }

  $profileImagePathMissingOrEmpty =
    (-not $hasProfileImagePathProperty) -or
    ([string]::IsNullOrWhiteSpace([string]$profileImagePath))

  if (-not $profileImagePathMissingOrEmpty) {
    Add-SkipReason -Sid $sid -RegPath $regPath -Reason "ProfileImagePath present" -Max $module.Params.maxSkipReasons
    continue
  }

  # RefCount guardrail
  $refCount = $null
  if ($props.PSObject.Properties.Name -contains 'RefCount') { $refCount = $props.RefCount }

  if ($module.Params.requireRefCountZeroIfPresent) {
    if ($null -ne $refCount -and [int]$refCount -ne 0) {
      Add-SkipReason -Sid $sid -RegPath $regPath -Reason "RefCount present and non-zero" -Max $module.Params.maxSkipReasons
      continue
    }
  }

  # Record match
  $module.Result.matchedCount++

  $module.Result.staleEntries += @{
    sid     = $sid
    regPath = $regPath
    reason  = "ProfileImagePath missing/empty"
    details = @{
      profileImagePathPropertyPresent = $hasProfileImagePathProperty
      refCount = $refCount
      hiveLoaded = (Test-HiveLoaded -Sid $sid)
      isBakKey = (Test-BakKey -Sid $sid)
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

  if ($module.Result.errors.Count -gt 0) {
    $module.FailJson("One or more stale ProfileList entries failed to remove. See 'errors' for details.")
  }
}

$module.ExitJson()
