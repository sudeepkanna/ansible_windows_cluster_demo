# win_cluster_membership_info.ps1
# Purpose: Check whether the local node is a member of any failover cluster.
# Parameters: none
# Outputs:
# - member: true if the local node is part of a cluster
# - cluster_name: name of the cluster when member is true
# - module_present: true if FailoverClusters module is available

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{} }
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # No parameters for this module.
$moduleName = "FailoverClusters"

try {
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    # Fall back to registry check when FailoverClusters is unavailable.
    $clusterName = (Get-ItemProperty -Path "HKLM:\\Cluster" -Name ClusterName -ErrorAction SilentlyContinue).ClusterName
    $module.Result.module_present = $false
    $module.Result.registry_fallback_used = $true
    if ($clusterName) {
      $module.Result.member = $true
      $module.Result.cluster_name = $clusterName
    } else {
      $module.Result.member = $false
    }
    $module.Result.changed = $false
    $module.ExitJson()
  }
  Import-Module $moduleName -ErrorAction Stop # Required for Get-Cluster.

  $cluster = Get-Cluster -ErrorAction SilentlyContinue
  if ($null -ne $cluster) {
    $module.Result.member = $true
    $module.Result.cluster_name = $cluster.Name
  } else {
    $module.Result.member = $false
  }
  $module.Result.module_present = $true
  $module.Result.registry_fallback_used = $false
  $module.Result.changed = $false
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
