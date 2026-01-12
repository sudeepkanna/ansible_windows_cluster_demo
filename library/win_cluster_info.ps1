
# win_cluster_info.ps1
# Purpose: Query whether a named Windows Failover Cluster exists.
# Parameters:
# - name (str, required): Cluster name
# Outputs:
# - exists: true if the cluster exists, false otherwise
# - module_present: true if FailoverClusters is available

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{ name = @{ type="str"; required=$true } } }
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.
$moduleName = "FailoverClusters"
try {
  # If the FailoverClusters module is missing, report absence without failing.
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.Result.module_present = $false
    $module.Result.exists = $false
    $module.Result.changed = $false
    $module.ExitJson()
  }
  Import-Module $moduleName -ErrorAction Stop # Required for Get-Cluster.

  # Explicit existence check; avoid exceptions for control flow.
  $cluster = Get-Cluster -Name $module.Params.name -ErrorAction SilentlyContinue
  $module.Result.exists = ($null -ne $cluster)
  $module.Result.module_present = $true
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
