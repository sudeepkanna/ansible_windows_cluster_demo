#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic

<#
DOCUMENTATION:
---
module: win_stale_usrProfile_cleanup
short_description: Detect and optionally remove stale ProfileList entries where ProfileImagePath is missing/empty
description:
  - Scans the Windows ProfileList registry hive at C(HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList)
    and detects broken profile entries that commonly break C(ansible.windows.win_user_profile).
  - An entry is considered stale when C(ProfileImagePath) is missing or empty.
  - The module applies multiple guardrails to avoid touching valid or in-use profiles.
  - Supports audit-only mode (C(report)) and enforcement mode (C(absent)).
  - Collects warnings and errors during processing and fails only at the end (when configured) to provide full visibility.

options:
  state:
    description:
      - C(report) audits and returns detected stale entries without making changes.
      - C(absent) removes detected stale entries.
    type: str
    choices: [report, absent]
    default: report

  validateSidFormat:
    description:
      - Ensures each ProfileList subkey name parses as a valid Windows SID.
    type: bool
    default: true

  requireUserSidPrefix:
    description:
      - Restricts processing to C(S-1-5-21-*) SIDs (local or domain users/groups created in SAM/AD).
      - Helps avoid touching service, system, or virtual identities.
    type: bool
    default: true

  skipBakKeys:
    description:
      - Skips keys ending with C(.bak) that may appear during Windows profile repair scenarios.
    type: bool
    default: true

  protectWellKnownSids:
    description:
      - Protects well-known system SIDs: C(S-1-5-18), C(S-1-5-19), C(S-1-5-20).
    type: bool
    default: true

  requireHiveNotLoaded:
    description:
      - Requires that C(HKEY_USERS\<SID>) does not exist, meaning the user hive is not loaded.
      - Prevents modifying profiles in active use.
    type: bool
    default: true

  requireUnmappedSid:
    description:
      - Requires that SID-to-account translation indicates the SID is unmapped (user deleted).
      - On domain-joined systems, SID translation may involve DC connectivity; failures are treated as unknown by default (safe).
    type: bool
    default: true

  treatSidLookupFailureAsUnmapped:
    description:
      - If true, non-IdentityNotMapped SID translation failures are treated as unmapped.
      - WARNING: This reduces safety, especially on domain-joined systems when DC is unreachable.
    type: bool
    default: false

  failOnDomainLookupFailure:
    description:
      - If true and the host is domain-joined, the module fails at the end if SID translation encounters
        domain/DC lookup failures. No unsafe deletions are performed due to such failures unless
        C(treatSidLookupFailureAsUnmapped=true).
    type: bool
    default: false

  domainLookupFailureThreshold:
    description:
      - Minimum number of domain/DC lookup failures that triggers a failure when C(failOnDomainLookupFailure=true).
    type: int
    default: 1

  requireRefCountZeroIfPresent:
    description:
      - If C(RefCount) exists, requires it to be C(0) before qualifying the entry as stale.
    type: bool
    default: true

notes:
  - This module only removes ProfileList registry keys; it does not delete profile folders and does not call DeleteProfileW.
  - On domain-joined servers, SID-to-account translation may require contacting a Domain Controller. If DC connectivity
    is unavailable, translation can fail with errors other than IdentityNotMappedException. By default, such failures
    are treated as unknown and entries are skipped (safe). Enable C(failOnDomainLookupFailure=true) for strict pipelines.

seealso:
  - module: ansible.windows.win_user_profile

author:
  - Your Team

EXAMPLES:
---
- name: Audit stale ProfileList entries
  win_stale_usrProfile_cleanup:
    state: report

- name: Remove stale ProfileList entries safely
  win_stale_usrProfile_cleanup:
    state: absent

- name: Strict mode - fail pipeline if domain/DC lookup fails
  win_stale_usrProfile_cleanup:
    state: absent
    failOnDomainLookupFailure: true
    domainLookupFailureThreshold: 1

- name: Aggressive mode (NOT recommended) - treat lookup failures as unmapped
  win_stale_usrProfile_cleanup:
    state: absent
    treatSidLookupFailureAsUnmapped: true

RETURN:
---
scannedKeyCount:
  description: Number of ProfileList subkeys scanned.
  returned: always
  type: int
staleEntries:
  description: List of detected stale entries (audit output).
  returned: always
  type: list
  elements: dict
removedSids:
  description: List of SIDs removed when state=absent.
  returned: when state=absent
  type: list
  elements: str
warnings:
  description: Non-fatal issues encountered during processing.
  returned: always
  type: list
  elements: str
domainLookupFailures:
  description: Domain/DC lookup failures detected during SID translation (if any).
  returned: always
  type: list
  elements: str
errors:
  description: Errors encountered during removal; if non-empty in enforcement mode, module fails at end.
  returned: always
  type: list
  elements: str
#>
#>

# -----------------------------
# Spec (camelCase params)
# -----------------------------
$spec = @{
  options = @{
    state = @{ type = "str"; default = "report"; choices = @("report","absent") }

    validateSidFormat = @{ type = "bool"; default = $true }
    requireUserSidPrefix = @{ type = "bool"; default = $true }
    skipBakKeys = @{ type = "bool"; default = $true }
    protectWellKnownSids = @{ type = "bool"; default = $true }

    requireHiveNotLoaded = @{ type = "bool"; default = $true }

    requireUnmappedSid = @{ type = "bool"; default = $true }
    treatSidLookupFailureAsUnmapped = @{ type = "bool"; default = $false }

    failOnDomainLookupFailure = @{ type = "bool"; default = $false }
    domainLookupFailureThreshold = @{ type = "int"; default = 1 }

    requireRefCountZeroIfPresent = @{ type = "bool"; default = $true }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# -----------------------------
# Results (better naming)
# -----------------------------
$module.Result.changed = $false
$module.Result.scannedKeyCount = 0
$module.Result.staleEntries = @()         # [{ sid, regPath, reason, details }]
$module.Result.removedSids = @()
$module.Result.warnings = @()
$module.Result.domainLookupFailures = @()
$module.Result.errors = @()

# -----------------------------
# Constants
# -----------------------------
$profileListRoot = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$wellKnownSids = @("S-1-5-18","S-1-5-19","S-1-5-20")

# -----------------------------
# Helper functions (approved verbs)
# -----------------------------

function Test-SidFormat {
  param([string]$sid)
  try {
    $null = New-Object System.Security.Principal.SecurityIdentifier($sid)
    return $true
  } catch {
    return $false
  }
}

function Test-UserSidPrefix {
  param([string]$sid)
  return ($sid -like "S-1-5-21-*")
}

function Test-BakKey {
  param([string]$sid)
  return ($sid -like "*.bak")
}

function Test-HiveLoaded {
  param([string]$sid)
  return (Test-Path -LiteralPath ("Registry::HKEY_USERS\" + $sid))
}

function Test-DomainJoined {
  try {
    return (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
  } catch {
    return $false
  }
}

function Test-DomainLookupFailure {
  param([System.Exception]$exception)

  $typeName = $exception.GetType().FullName
  $message = $exception.Message

  # Common DC / trust / RPC / DNS failure indicators during identity lookup
  $patterns = @(
    "RPC server is unavailable",
    "The RPC server is unavailable",
    "There are currently no logon servers available",
    "No such domain",
    "The trust relationship",
    "The specified domain either does not exist",
    "The network path was not found",
    "A domain controller could not be contacted",
    "DNS name does not exist"
  )

  if ($typeName -in @("System.Runtime.InteropServices.COMException","System.ComponentModel.Win32Exception")) {
    return $true
  }

  foreach ($p in $patterns) {
    if ($message -like "*$p*") { return $true }
  }

  return $false
}

function Test-SidResolvesToAccount {
  param(
    [string]$sid,
    [ref]$warningMessage,
    [ref]$domainLookupFailureMessage,
    [bool]$treatLookupFailureAsUnmapped
  )

  # Return values:
  #   $true  -> resolves to an account
  #   $false -> does not resolve (IdentityNotMapped) OR treated as unmapped
  #   $null  -> unknown (lookup failure; safe default is skip)
  try {
    $sidObject = New-Object System.Security.Principal.SecurityIdentifier($sid)
    $null = $sidObject.Translate([System.Security.Principal.NTAccount])
    return $true
  }
  catch [System.Security.Principal.IdentityNotMappedException] {
    return $false
  }
  catch {
    $ex = $_.Exception

    if (Test-DomainLookupFailure -exception $ex) {
      $domainLookupFailureMessage.Value = "Domain/DC lookup failure translating SID '$sid': $($ex.GetType().FullName): $($ex.Message)"
    } else {
      $warningMessage.Value = "SID translation failed for '$sid': $($ex.GetType().FullName): $($ex.Message)"
    }

    if ($treatLookupFailureAsUnmapped) { return $false }
    return $null
  }
}

function Get-ProfileListKey {
  param([string]$registryPath)
  try {
    return Get-Item -LiteralPath $registryPath -ErrorAction Stop
  } catch {
    return $null
  }
}

function Get-RegistryValue {
  param(
    [Microsoft.Win32.RegistryKey]$registryKey,
    [string]$valueName
  )
  try {
    return $registryKey.GetValue($valueName, $null)
  } catch {
    return $null
  }
}

function Remove-ProfileListKey {
  param(
    [string]$registryPath,
    [string]$sid,
    [ref]$errorMessage
  )
  try {
    Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction Stop
    return $true
  } catch {
    $errorMessage.Value = "Failed to remove ProfileList key '$registryPath' for SID '$sid': $($_.Exception.Message)"
    return $false
  }
}

# -----------------------------
# Environment
# -----------------------------
$domainJoined = Test-DomainJoined

# -----------------------------
# Enumerate ProfileList keys
# -----------------------------
try {
  $profileKeys = Get-ChildItem -LiteralPath $profileListRoot -ErrorAction Stop
} catch {
  $module.FailJson("Failed to enumerate ProfileList registry '$profileListRoot': $($_.Exception.Message)")
}

# -----------------------------
# Detection loop (minimize registry I/O)
# -----------------------------
foreach ($profileKey in $profileKeys) {
  $module.Result.scannedKeyCount++

  $sid = $profileKey.PSChildName
  $regPath = $profileKey.PSPath

  # Guardrail: protect system SIDs
  if ($module.Params.protectWellKnownSids -and ($wellKnownSids -contains $sid)) { continue }

  # Guardrail: validate SID format
  if ($module.Params.validateSidFormat) {
    if (-not (Test-SidFormat -sid $sid)) { continue }
  }

  # Guardrail: skip .bak
  if ($module.Params.skipBakKeys) {
    if (Test-BakKey -sid $sid) { continue }
  }

  # Guardrail: restrict to S-1-5-21-* (local/domain users)
  if ($module.Params.requireUserSidPrefix) {
    if (-not (Test-UserSidPrefix -sid $sid)) { continue }
  }

  # Guardrail: do not touch loaded hive
  if ($module.Params.requireHiveNotLoaded) {
    if (Test-HiveLoaded -sid $sid) { continue }
  }

  # Read registry key once
  $keyItem = Get-ProfileListKey -registryPath $regPath
  if ($null -eq $keyItem) {
    $module.Result.warnings += "Unable to open registry key '$regPath' (SID '$sid'). Skipping for safety."
    continue
  }

  # Convert PowerShell registry provider item to underlying RegistryKey to read values without repeated Get-ItemProperty calls
  $registryKey = $keyItem.GetValueNames() | Out-Null; $keyItem.PSObject.BaseObject

  # NOTE: On some PS versions, BaseObject is the RegistryKey; if not, fall back to Get-ItemProperty once
  $baseObject = $keyItem.PSObject.BaseObject
  $profileImagePath = $null
  $refCount = $null
  $stateValue = $null
  $flagsValue = $null

  if ($baseObject -is [Microsoft.Win32.RegistryKey]) {
    $profileImagePath = Get-RegistryValue -registryKey $baseObject -valueName "ProfileImagePath"
    $refCount = Get-RegistryValue -registryKey $baseObject -valueName "RefCount"
    $stateValue = Get-RegistryValue -registryKey $baseObject -valueName "State"
    $flagsValue = Get-RegistryValue -registryKey $baseObject -valueName "Flags"
  } else {
    # Fallback: single Get-ItemProperty call (still one call per key)
    try {
      $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
      $profileImagePath = $props.ProfileImagePath
      if ($props.PSObject.Properties.Name -contains "RefCount") { $refCount = $props.RefCount }
      if ($props.PSObject.Properties.Name -contains "State") { $stateValue = $props.State }
      if ($props.PSObject.Properties.Name -contains "Flags") { $flagsValue = $props.Flags }
    } catch {
      $module.Result.warnings += "Unable to read properties for '$regPath' (SID '$sid'). Skipping for safety."
      continue
    }
  }

  # Core condition: ProfileImagePath missing/empty
  if (-not [string]::IsNullOrWhiteSpace([string]$profileImagePath)) { continue }

  # Guardrail: RefCount == 0 if present
  if ($module.Params.requireRefCountZeroIfPresent) {
    if ($null -ne $refCount -and [int]$refCount -ne 0) { continue }
  }

  # Guardrail: require unmapped SID (deleted user)
  if ($module.Params.requireUnmappedSid) {
    $warn = $null
    $dcFail = $null

    $resolves = Test-SidResolvesToAccount `
      -sid $sid `
      -warningMessage ([ref]$warn) `
      -domainLookupFailureMessage ([ref]$dcFail) `
      -treatLookupFailureAsUnmapped $module.Params.treatSidLookupFailureAsUnmapped

    if ($null -ne $warn) { $module.Result.warnings += $warn }

    if ($null -ne $dcFail) {
      $module.Result.domainLookupFailures += $dcFail
      if (-not $module.Params.treatSidLookupFailureAsUnmapped) {
        # Safe default: unknown -> skip
        continue
      }
    }

    if ($resolves -eq $true) { continue }
    if ($null -eq $resolves) { continue }
    # resolves == $false -> ok
  }

  # Record stale entry (audit output)
  $module.Result.staleEntries += @{
    sid = $sid
    regPath = $regPath
    reason = "ProfileImagePath missing/empty"
    details = @{
      refCount = $refCount
      state = $stateValue
      flags = $flagsValue
    }
  }
}

# -----------------------------
# Enforcement / removal phase
# -----------------------------
if ($module.Params.state -eq "absent") {

  foreach ($entry in $module.Result.staleEntries) {

    if ($module.CheckMode) {
      # In check mode, we report changes but do not delete
      $module.Result.changed = $true
      continue
    }

    $err = $null
    $ok = Remove-ProfileListKey -registryPath $entry.regPath -sid $entry.sid -errorMessage ([ref]$err)

    if ($ok) {
      $module.Result.removedSids += $entry.sid
      $module.Result.changed = $true
    } else {
      $module.Result.errors += $err
      # Continue processing; fail at end
    }
  }

  # Fail at end if any removal errors occurred
  if ($module.Result.errors.Count -gt 0) {
    $module.FailJson("One or more ProfileList keys failed to remove. See 'errors' in the result for details.")
  }
}

# -----------------------------
# Optional strict DC failure mode (safe)
# -----------------------------
if ($module.Params.failOnDomainLookupFailure -and $domainJoined) {
  if ($module.Result.domainLookupFailures.Count -ge [int]$module.Params.domainLookupFailureThreshold) {
    $module.FailJson("Domain/DC lookup failures were detected during SID translation. No unsafe deletions were performed due to lookup failures. See 'domainLookupFailures' in the result.")
  }
}

$module.ExitJson()
