# win_cluster_quorum_info.ps1
# Purpose: Return current cluster quorum configuration.
# Parameters:
# - cluster_name (str, required)
# Outputs:
# - quorum_type
# - witness_path (when applicable)

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{
  cluster_name=@{type="str";required=$true}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.
$moduleName = "FailoverClusters"

try {
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure Failover Clustering features are installed.")
  }
  Import-Module $moduleName -ErrorAction Stop # Required for Get-ClusterQuorum.

  $q = Get-ClusterQuorum -Cluster $module.Params.cluster_name -ErrorAction Stop
  $module.Result.quorum_type = $q.QuorumType

  $witnessPath = $null
  if ($q.QuorumResource) {
    try {
      $witnessPath = (Get-ClusterParameter -InputObject $q.QuorumResource -Name SharePath -ErrorAction Stop).Value
    } catch {
      $witnessPath = $null
    }
  }
  $module.Result.witness_path = $witnessPath
  $module.Result.changed = $false
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
