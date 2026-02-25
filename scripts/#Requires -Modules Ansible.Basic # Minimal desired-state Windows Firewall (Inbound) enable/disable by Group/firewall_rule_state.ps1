#!powershell
#AnsibleRequires -CSharpUtil Ansible.Basic
#Requires -Modules Ansible.Basic

$ErrorActionPreference = "Stop"

# -----------------------------
# Module specification
# -----------------------------
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
                name    = @{ type = "str";  required = $true }  # INTERNAL Name
                enabled = @{ type = "bool"; required = $true }
            }
            default = @()
        }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

# -----------------------------
# Helper: detect resource group
# -----------------------------
function Use-InternalGroup([string]$pattern) {
    if ($null -eq $pattern) { return $false }
    $p = $pattern.ToLower()
    return (
        $p.StartsWith("@") -or
        $p.StartsWith("ms-resource:") -or
        $p.StartsWith("%systemroot%")
    )
}

try {
    $groups = $module.Params.group
    $rules  = $module.Params.rule

    if ($null -eq $groups) { $groups = @() }
    if ($null -eq $rules)  { $rules  = @() }

    # -----------------------------
    # Snapshot ALL inbound rules
    # -----------------------------
    $firewallConfig = Get-NetFirewallRule -Direction Inbound | Select-Object `
        Name,
        DisplayName,
        Group,
        DisplayGroup,
        @{ n='Enabled'; e={ $_.Enabled -eq 'True' } }

    # key = internal Name
    $diff = @{}
    $changed = $false
    $affected = @()

    # -----------------------------
    # 1) Apply GROUP rules first
    # -----------------------------
    foreach ($item in $groups) {
        $pattern = $item.name
        $desired = [bool]$item.enabled

        foreach ($r in $firewallConfig) {
            $field = if (Use-InternalGroup $pattern) {
                $r.Group
            } else {
                $r.DisplayGroup
            }

            if ($null -eq $field) { continue }

            if ($field -like $pattern) {
                if ($r.Enabled -ne $desired) {
                    $diff[$r.Name] = @{
                        rule    = $r
                        desired = $desired
                        source  = "group"
                        match   = $field
                        pattern = $pattern
                    }
                }
            }
        }
    }

    # -----------------------------
    # 2) Apply RULE overrides (Name is UNIQUE)
    # -----------------------------
    foreach ($item in $rules) {
        $ruleName = $item.name
        $desired  = [bool]$item.enabled

        $matches = $firewallConfig | Where-Object { $_.Name -eq $ruleName }

        if ($matches.Count -eq 0) {
            $module.FailJson("Rule with Name '$ruleName' not found")
        }
        elseif ($matches.Count -gt 1) {
            $module.FailJson("Internal error: multiple rules found with Name '$ruleName'")
        }

        $r = $matches[0]

        if ($r.Enabled -ne $desired -or $diff.ContainsKey($r.Name)) {
            $diff[$r.Name] = @{
                rule    = $r
                desired = $desired
                source  = "rule"
                match   = $r.Name
                pattern = $ruleName
            }
        }
    }

    # -----------------------------
    # 3) Apply or preview changes
    # -----------------------------
    foreach ($entry in $diff.GetEnumerator()) {
        $r = $entry.Value.rule
        $desired = $entry.Value.desired

        if (-not $module.CheckMode) {
            $val = if ($desired) { "True" } else { "False" }
            Set-NetFirewallRule -Name $r.Name -Enabled $val | Out-Null
        }

        $changed = $true
        $affected += @{
            name         = $r.Name
            displayname  = $r.DisplayName
            group        = $r.Group
            displaygroup = $r.DisplayGroup
            from         = $r.Enabled
            to           = $desired
            source       = $entry.Value.source
            pattern      = $entry.Value.pattern
        }
    }

    # -----------------------------
    # Return result
    # -----------------------------
    $module.Result.changed = $changed
    $module.Result.affected_rules = $affected
    $module.ExitJson()
}
catch {
    $module.FailJson("win_firewall_test failed: $($_.Exception.Message)")
}
