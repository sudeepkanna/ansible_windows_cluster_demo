
# win_cluster_ensure.ps1
# Purpose: Ensure a Windows Failover Cluster exists with the provided name, nodes, and static IP.
# Note: For a more modular flow, prefer win_cluster_info (check) + win_cluster_create (create).
# Parameters (Ansible options):
# - name (str, required): Cluster name
# - nodes (list[str], required): Member nodes to create cluster with
# - static_address (str, required): Cluster static IP
# Outputs (via Ansible.Basic):
# - exists: true if cluster already existed
# - changed: true if the module created the cluster

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{ 
  name=@{type="str";required=$true}
  nodes=@{type="list";elements="str";required=$true}
  static_address=@{type="str";required=$true}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.
$moduleName = "FailoverClusters"
try {
  # Ensure the FailoverClusters module is available before invoking cluster cmdlets.
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure Failover Clustering features are installed.")
  }
  Import-Module $moduleName -ErrorAction Stop # Required for Get-Cluster/New-Cluster.

  # Explicit existence check; do not rely on exceptions for control flow.
  $cluster = Get-Cluster -Name $module.Params.name -ErrorAction SilentlyContinue
  if ($null -ne $cluster) {
    $module.Result.exists = $true
    $module.Result.changed = $false
    $module.ExitJson()
  }

  # Cluster not found — create it and report change.
  New-Cluster -Name $module.Params.name -Node $module.Params.nodes -StaticAddress $module.Params.static_address -NoStorage -ErrorAction Stop | Out-Null
  $module.Result.changed = $true
  $module.Result.exists = $true
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
