# win_cluster_create.ps1
# Purpose: Create a Windows Failover Cluster when it does not already exist.
# Parameters (Ansible options):
# - name (str, required): Cluster name
# - nodes (list[str], required): Member nodes to create cluster with
# - static_address (str, required): Cluster static IP
# Outputs (via Ansible.Basic):
# - exists: true if the cluster already exists or was created
# - changed: true when a new cluster is created

Import-Module Ansible.Basic
$spec = @{ options = @{
  name=@{type="str";required=$true}
  nodes=@{type="list";elements="str";required=$true}
  static_address=@{type="str";required=$true}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec)

try {
  $moduleName = "FailoverClusters"
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure Failover Clustering features are installed.")
  }
  Import-Module $moduleName -ErrorAction Stop # Required for Get-Cluster/New-Cluster.

  # Check for an existing cluster without using exceptions for control flow.
  $cluster = Get-Cluster -Name $module.Params.name -ErrorAction SilentlyContinue
  if ($null -ne $cluster) {
    $module.Result.exists = $true
    $module.Result.changed = $false
    $module.ExitJson()
  }

  # Create the cluster only when it does not already exist.
  New-Cluster -Name $module.Params.name -Node $module.Params.nodes -StaticAddress $module.Params.static_address -NoStorage -ErrorAction Stop | Out-Null
  $module.Result.changed = $true
  $module.Result.exists = $true
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
