# win_cluster_ensure.ps1
# Purpose: Ensure a Windows Failover Cluster exists with the provided name, nodes, and static IP.
# Note: The role currently prefers win_cluster_info + win_cluster_create, but this module is kept consistent for direct use.

Import-Module Ansible.Basic

$spec = @{
  options = @{
    name = @{ type = "str"; required = $true }
    nodes = @{ type = "list"; elements = "str"; required = $true }
    static_address = @{ type = "str"; required = $true }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

try {
  $moduleName = "FailoverClusters"
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure Failover Clustering features are installed.")
  }

  Import-Module $moduleName -ErrorAction Stop

  $cluster = Get-Cluster -Name $module.Params.name -ErrorAction SilentlyContinue
  if ($null -ne $cluster) {
    $module.Result.exists = $true
    $module.Result.changed = $false
    $module.ExitJson()
  }

  if ($module.CheckMode) {
    $module.Result.exists = $false
    $module.Result.changed = $true
    $module.Result.planned_action = "create"
    $module.ExitJson()
  }

  New-Cluster `
    -Name $module.Params.name `
    -Node $module.Params.nodes `
    -StaticAddress $module.Params.static_address `
    -NoStorage `
    -ErrorAction Stop | Out-Null

  $module.Result.changed = $true
  $module.Result.exists = $true
  $module.ExitJson()
}
catch {
  $module.FailJson($_.Exception.Message)
}
