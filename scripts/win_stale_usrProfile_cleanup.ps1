#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

$ErrorActionPreference = 'Stop'
$ProgressPreference   = 'SilentlyContinue'

$spec = @{
  options = @{
    state = @{ type = "str"; choices = @("report", "absent"); default = "report" }

    skipBakKeys = @{ type = "bool"; default = $true }
    requireUserSidPrefix = @{ type = "bool"; default = $true }
    requireHiveNotLoaded = @{ type = "bool"; default = $true }
    requireRefCountZeroIfPresent = @{ type = "bool"; default = $true }

    # If true, stale entries that fail guardrails are still reported in blockedEntries
    reportBlockedEntries = @{ type = "bool"; default = $true }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$module.Result.changed          = $false
$module.Result.scannedKeyCount  = 0
$module.Result.staleEntries     = @()   # stale & eligible (or just stale, depending on view below)
$module.Result.blockedEntries   = @()   # stale but blocked by guardrails
$module.Result.removedSids      = @()
$module.Result.warnings         = @()
$module.Result.errors           = @()

$profileListRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$wellKnownSids   = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

function Test-UserSidPrefix { param([string]$Sid) return ($Sid -like 'S-1-5-21-*') }
function Test-BakKey { param([string]$Sid) return ($Sid -like '*.bak') }
function Test-HiveLoaded { param([string]$Sid) return (Test-Path -LiteralPath ("Registry::HKEY_USERS\$Sid")) }

function Add-Entry {
  param(
    [string]$ListName,
    [string]$Sid,
    [string]$RegPath,
    [string]$Reason,
    [hashtable]$Details
  )
  $entry = @{
    sid     = $Sid
    regPath = $RegPath
    reason  = $Reason
    details = $Details
  }

  if ($ListName -eq 'stale')   { $module.Result.staleEntries   += $entry }
  if ($ListName -eq 'blocked') { $module.Result.blockedEntries += $entry }
}

try {
  $profileKeys = Get-ChildItem -LiteralPath $profileListRoot
} catch {
  $module.FailJson("Failed to enumerate ProfileList registry: $($_.Exception.Message)")
}

foreach ($key in $profileKeys) {
  $module.Result.scannedKeyCount++

  $sid     = $key.PSChildName
  $regPath = $key.PSPath

  # Read properties ONCE
  $props = $null
  try {
    $props = Get-ItemProperty -LiteralPath $regPath
  } catch {
    $module.Result.warnings += "Unable to read ProfileList key '$regPath' (SID $sid). Skipping."
    continue
  }

  $profileImagePath = $props.ProfileImagePath
  $refCount = $null
  if ($props.PSObject.Properties.Name -contains 'RefCount') { $refCount = $props.RefCount }

  $hiveLoaded = Test-HiveLoaded -Sid $sid
  $isBakKey   = Test-BakKey -Sid $sid
  $isUserSid  = Test-UserSidPrefix -Sid $sid
  $isWellKnown = ($wellKnownSids -contains $sid)

  # Determine if it is stale (your primary condition)
  $isStale = [string]::IsNullOrWhiteSpace([string]$profileImagePath)

  if (-not $isStale) {
    continue
  }

  # Evaluate guardrails, but DO NOT lose reporting
  $blockReasons = @()

  if ($isWellKnown) { $blockReasons += "Well-known system SID" }

  if ($module.Params.skipBakKeys -and $isBakKey) { $blockReasons += "Key ends with .bak (skipBakKeys=true)" }

  if ($module.Params.requireUserSidPrefix -and (-not $isUserSid)) {
    $blockReasons += "SID not in S-1-5-21-* scope (requireUserSidPrefix=true)"
  }

  if ($module.Params.requireHiveNotLoaded -and $hiveLoaded) {
    $blockReasons += "User hive is loaded under HKEY_USERS (requireHiveNotLoaded=true)"
  }

  if ($module.Params.requireRefCountZeroIfPresent -and ($null -ne $refCount) -and ([int]$refCount -ne 0)) {
    $blockReasons += "RefCount is not 0 (requireRefCountZeroIfPresent=true)"
  }

  $details = @{
    profileImagePathPresent = $false
    profileImagePath        = $profileImagePath
    refCount                = $refCount
    hiveLoaded              = $hiveLoaded
    isBakKey                = $isBakKey
    isUserSidInScope        = $isUserSid
    isWellKnownSid          = $isWellKnown
  }

  if ($blockReasons.Count -gt 0) {
    if ($module.Params.reportBlockedEntries) {
      Add-Entry -ListName 'blocked' -Sid $sid -RegPath $regPath -Reason ("Blocked: " + ($blockReasons -join "; ")) -Details $details
    }
    continue
  }

  # Eligible stale entry
  Add-Entry -ListName 'stale' -Sid $sid -RegPath $regPath -Reason 'ProfileImagePath missing/empty' -Details $details
}

# Enforcement
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
    } catch {
      $module.Result.errors += "Failed to remove $($entry.sid): $($_.Exception.Message)"
    }
  }

  if ($module.Result.errors.Count -gt 0) {
    $module.FailJson("One or more stale ProfileList entries failed to remove. See 'errors' for details.")
  }
}

$module.ExitJson()
