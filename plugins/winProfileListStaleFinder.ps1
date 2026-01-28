#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

<#
.SYNOPSIS
  Finds and optionally removes stale Windows user profile registry entries.

.DESCRIPTION
  Scans:
    HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList

  Identifies "broken" entries that commonly break ansible.windows.win_user_profile:
    - ProfileImagePath is missing or empty

  Safety guardrails (defaults ON):
    - Only consider user SIDs (S-1-5-21-*)
    - Skip well-known system SIDs (S-1-5-18/19/20)
    - Skip .bak keys (unless disabled)
    - Require SID does not resolve to an account (user deleted)
    - Require HKU\<SID> hive is NOT loaded (prevents instability)
    - If RefCount exists, require it to be 0

  Modes:
    - state=report : audit only, return candidates
    - state=absent : remove candidate registry keys

.NOTES
  Use this module as a pre-clean step before calling ansible.windows.win_user_profile.
#>

# -------------------------------------------------------------------
# Module argument specification (camelCase options)
# -------------------------------------------------------------------
$spec = @{
  options = @{

    # report = detect only, absent = remove detected candidates
    state = @{
      type = "str"
      default = "report"
      choices = @("report", "absent")
    }

    # Guardrails
    validateSidFormat = @{ type = "bool"; default = $true }          # SID must parse as SecurityIdentifier
    requireUserSidPrefix = @{ type = "bool"; default = $true }       # require S-1-5-21-*
    skipBakKeys = @{ type = "bool"; default = $true }                # skip *.bak keys
    protectWellKnownSids = @{ type = "bool"; default = $true }       # protect system SIDs
    requireUnmappedSid = @{ type = "bool"; default = $true }         # SID->NTAccount translation must fail
    requireHiveNotLoaded = @{ type = "bool"; default = $true }       # HKU\<SID> must not exist
    requireRefCountZeroIfPresent = @{ type = "bool"; default = $true } # RefCount==0 if present
  }

  supports_check_mode = $true
}

# Create Ansible module instance
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# -------------------------------------------------------------------
# Result initialization
# -------------------------------------------------------------------
$module.Result.changed = $false
$module.Result.candidates = @()      # list of candidate keys (sid, regPath, reason)
$module.Result.removedSids = @()     # list of removed SIDs (when state=absent)
$module.Result.examinedCount = 0     # number of keys examined

# ProfileList registry root
$profileListRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"

# System SIDs that must never be removed
$wellKnownSids = @(
  "S-1-5-18", # LocalSystem
  "S-1-5-19", # LocalService
  "S-1-5-20"  # NetworkService
)

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

# Validate the key name is a real SID
function isValidSid {
  param([string]$sid)
  try {
    $null = New-Object System.Security.Principal.SecurityIdentifier($sid)
    return $true
  }
  catch {
    return $false
  }
}

# Only consider user SIDs (local or domain users/groups created in SAM/AD)
function isUserSid {
  param([string]$sid)
  return $sid -like "S-1-5-21-*"
}

# Detect .bak keys (profile corruption recovery keys)
function isBakKey {
  param([string]$sid)
  return $sid -like "*.bak"
}

# Check whether SID still maps to an account (DOMAIN\User or MACHINE\User)
function sidResolvesToAccount {
  param([string]$sid)
  try {
    $sidObject = New-Object System.Security.Principal.SecurityIdentifier($sid)
    $null = $sidObject.Translate([System.Security.Principal.NTAccount])
    return $true
  }
  catch {
    return $false
  }
}

# NEW GUARDRAIL: Check if user hive is currently loaded
# If HKU\<SID> exists, the profile is loaded → DO NOT TOUCH
function isHiveLoaded {
  param([string]$sid)
  return Test-Path -LiteralPath ("Registry::HKEY_USERS\" + $sid)
}

# Safely read ProfileImagePath; return $null if missing/empty
function getProfileImagePathSafe {
  param([string]$registryPath)
  try {
    $value = (Get-ItemProperty -LiteralPath $registryPath `
                                -Name ProfileImagePath `
                                -ErrorAction Stop).ProfileImagePath
    if ([string]::IsNullOrWhiteSpace($value)) {
      return $null
    }
    return $value
  }
  catch {
    return $null
  }
}

# Safely read RefCount; return $null if missing
function getRefCountSafe {
  param([string]$registryPath)
  try {
    return (Get-ItemProperty -LiteralPath $registryPath `
                             -Name RefCount `
                             -ErrorAction Stop).RefCount
  }
  catch {
    return $null
  }
}

# -------------------------------------------------------------------
# Enumerate ProfileList keys
# -------------------------------------------------------------------
try {
  $profileKeys = Get-ChildItem -LiteralPath $profileListRoot -ErrorAction Stop
}
catch {
  $module.FailJson("Failed to enumerate ProfileList registry: $($_.Exception.Message)")
}

# -------------------------------------------------------------------
# Main detection loop
# -------------------------------------------------------------------
foreach ($profileKey in $profileKeys) {

  $module.Result.examinedCount++

  # Registry subkey name is the SID (or sometimes SID.bak)
  $sid = $profileKey.PSChildName

  # Guardrail: validate SID format (if enabled)
  if ($module.Params.validateSidFormat) {
    if (-not (isValidSid -sid $sid)) { continue }
  }

  # Guardrail: skip .bak keys by default (conservative)
  if ($module.Params.skipBakKeys) {
    if (isBakKey -sid $sid) { continue }
  }

  # Guardrail: require user SID prefix (S-1-5-21-*)
  if ($module.Params.requireUserSidPrefix) {
    if (-not (isUserSid -sid $sid)) { continue }
  }

  # Guardrail: protect well-known system SIDs
  if ($module.Params.protectWellKnownSids -and ($wellKnownSids -contains $sid)) {
    continue
  }

  # Guardrail: require hive NOT loaded (HKU\<SID> must not exist)
  if ($module.Params.requireHiveNotLoaded) {
    if (isHiveLoaded -sid $sid) { continue }
  }

  # Candidate definition: ProfileImagePath missing/empty
  $profileImagePath = getProfileImagePathSafe -registryPath $profileKey.PSPath
  if (-not [string]::IsNullOrWhiteSpace($profileImagePath)) {
    continue
  }

  # Guardrail: require SID unmapped (account deleted)
  if ($module.Params.requireUnmappedSid) {
    if (sidResolvesToAccount -sid $sid) { continue }
  }

  # Guardrail: RefCount == 0 if present
  if ($module.Params.requireRefCountZeroIfPresent) {
    $refCount = getRefCountSafe -registryPath $profileKey.PSPath
    if ($null -ne $refCount -and $refCount -ne 0) { continue }
  }

  # Passed all guardrails: safe stale candidate
  $module.Result.candidates += @{
    sid     = $sid
    regPath = $profileKey.PSPath
    reason  = "ProfileImagePath missing/empty; user SID; hive not loaded; unmapped SID; safe RefCount"
  }
}

# -------------------------------------------------------------------
# Removal phase (state=absent)
# -------------------------------------------------------------------
if ($module.Params.state -eq "absent") {

  foreach ($candidate in $module.Result.candidates) {

    if (-not $module.CheckMode) {
      try {
        Remove-Item -LiteralPath $candidate.regPath `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
      }
      catch {
        $module.FailJson(
          "Failed to remove ProfileList key '$($candidate.regPath)' for SID '$($candidate.sid)': $($_.Exception.Message)"
        )
      }
    }

    $module.Result.removedSids += $candidate.sid
    $module.Result.changed = $true
  }
}

# -------------------------------------------------------------------
# Exit module
# -------------------------------------------------------------------
$module.ExitJson()
