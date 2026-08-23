# win_cluster_create.ps1
# Purpose: Create a Windows Failover Cluster when it does not already exist.

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

  # In check mode report what would change without creating the cluster.
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
