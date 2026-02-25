#Requires -Modules Ansible.Basic
# Minimal desired-state Windows Firewall (Inbound) enable/disable by Group/DisplayGroup with per-rule precedence.

$ErrorActionPreference = "Stop"

$spec = @{
  options = @{
    group = @{
      type     = "list"
      elements = "dict"
      required = $false
      options  = @{
        name    = @{ type = "str";  required = $true }
        enabled = @{ type = "bool"; required = $true }
      }
      default = @()
    }

    rule = @{
      type     = "list"
      elements = "dict"
      required = $false
      options  = @{
        name    = @{ type = "str";  required = $true }   # DisplayName exact match
        enabled = @{ type = "bool"; required = $true }
      }
      default = @()
    }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

function Normalize-Enabled([object]$v) {
  if ($v -is [bool]) { return [bool]$v }
  if ($null -eq $v) { return $false }
  return ($v.ToString().Trim().ToLower() -eq "true")
}

function Use-GroupField([string]$pattern) {
  if ($null -eq $pattern) { return $false }
  $p = $pattern.Trim().ToLower()
  return ($p.StartsWith("@") -or $p.StartsWith("ms-resource:") -or $p.StartsWith("%systemroot%"))
}

try {
  $groupTargets = $module.Params.group
  $ruleTargets  = $module.Params.rule

  if ($null -eq $groupTargets) { $groupTargets = @() }
  if ($null -eq $ruleTargets)  { $ruleTargets  = @() }

  # Snapshot: ALL inbound rules (enabled + disabled) with both group fields
  $firewallConfig = Get-NetFirewallRule -Direction Inbound | Select-Object `
    @{l='name';         e={$_.Name}},
    @{l='displayname';  e={$_.DisplayName}},
    @{l='group';        e={$_.Group}},
    @{l='displaygroup'; e={$_.DisplayGroup}},
    @{l='enabled';      e={ $_.Enabled -eq 'True' }}

  # differenceObject: key=rule internal name, value={ rule=<snapshot>, desired=<bool>, source='group'|'rule' }
  $differenceObject = @{}
  $changed = $false
  $affected = @()

  # 1) Apply GROUP targets first (bulk). Add rules where current != desired.
  foreach ($item in ($groupTargets | Where-Object { $_ })) {
    $pattern = [string]$item.name
    $desired = [bool]$item.enabled

    foreach ($r in $firewallConfig) {
      $field = if (Use-GroupField $pattern) { $r.group } else { $r.displaygroup }
      if ($null -eq $field) { continue }

      if ($field -like $pattern) {
        if ($r.enabled -ne $desired) {
          $differenceObject[$r.name] = @{
            rule    = $r
            desired = $desired
            source  = "group"
            matched = $field
            pattern = $pattern
          }
        }
      }
    }
  }

  # 2) Apply RULE targets second (precedence). Exact match by DisplayName (case-insensitive).
  foreach ($item in ($ruleTargets | Where-Object { $_ })) {
    $rname   = [string]$item.name
    $desired = [bool]$item.enabled

    $hit = $firewallConfig | Where-Object { $_.displayname -ieq $rname } | Select-Object -First 1
    if (-not $hit) {
      # Keep simple: fail fast if rule not found
      $module.FailJson("Rule override not found by DisplayName (inbound): '$rname'")
    }

    # Override always wins (even if it wasn't in group diff list)
    if (($differenceObject.ContainsKey($hit.name)) -or ($hit.enabled -ne $desired)) {
      $differenceObject[$hit.name] = @{
        rule    = $hit
        desired = $desired
        source  = "rule"
        matched = $hit.displayname
        pattern = $rname
      }
    }
  }

  # 3) Apply changes (or preview if check_mode)
  foreach ($entry in $differenceObject.GetEnumerator()) {
    $current = $entry.Value.rule
    $desired = [bool]$entry.Value.desired

    if (-not $module.CheckMode) {
      $val = if ($desired) { "True" } else { "False" }
      Set-NetFirewallRule -Name $current.name -Enabled $val | Out-Null
    }

    $changed = $true
    $affected += @{
      name         = $current.name
      displayname  = $current.displayname
      group        = $current.group
      displaygroup = $current.displaygroup
      from         = [bool]$current.enabled
      to           = $desired
      source       = $entry.Value.source
      match        = $entry.Value.matched
      pattern      = $entry.Value.pattern
    }
  }

  $module.ExitJson(@{
    changed = $changed
    affected_rules = $affected
  })
}
catch {
  $module.FailJson("Error: $($_.Exception.Message)", @{ exception = ($_ | Out-String) })
}
