
# win_cluster_quorum_ensure.ps1
# Purpose: Ensure the cluster quorum configuration matches the desired `mode` and `witness_path`.
# Parameters:
# - cluster_name (str, required)
# - mode (str, required)
# - witness_path (str, required when using a file share witness)
# Outputs:
# - changed: true if the module updated the quorum configuration

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{ 
  cluster_name=@{type="str";required=$true}
  mode=@{type="str";required=$true}
  witness_path=@{type="str";required=$false}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.
try {
  $moduleName = "FailoverClusters"
  # Ensure the FailoverClusters module is available before quorum operations.
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure Failover Clustering features are installed.")
  }
  Import-Module $moduleName -ErrorAction Stop # Required for Get-ClusterQuorum/Set-ClusterQuorum.

  $mode = $module.Params.mode
  $witnessPath = $module.Params.witness_path
  $allowedModes = @("NodeMajority", "NodeAndFileShareMajority", "FileShareWitness")
  if (-not ($allowedModes -contains $mode)) {
    $module.FailJson("Unsupported quorum mode '$mode'. Supported modes: " + ($allowedModes -join ", "))
  }

  $q = Get-ClusterQuorum -Cluster $module.Params.cluster_name -ErrorAction Stop # Current quorum settings.
  $desiredType = if ($mode -eq "NodeMajority") { "NodeMajority" } else { "NodeAndFileShareMajority" }

  $currentShare = $null
  if ($q.QuorumResource) {
    try {
      $currentShare = (Get-ClusterParameter -InputObject $q.QuorumResource -Name SharePath -ErrorAction Stop).Value # Current witness path.
    } catch {
      $currentShare = $null
    }
  }

  $needsChange = $false
  # Compare current and desired quorum configuration.
  if ($q.QuorumType -ne $desiredType) {
    $needsChange = $true
  }
  if ($desiredType -eq "NodeAndFileShareMajority") {
    if (-not $witnessPath) {
      $module.FailJson("witness_path must be set when quorum mode requires a file share witness.")
    }
    if ($currentShare -ne $witnessPath) {
      $needsChange = $true
    }
  }

  if ($needsChange) {
    if ($desiredType -eq "NodeMajority") {
      Set-ClusterQuorum -Cluster $module.Params.cluster_name -NodeMajority -ErrorAction Stop # Set node majority.
    } else {
      Set-ClusterQuorum -Cluster $module.Params.cluster_name -NodeAndFileShareMajority -FileShareWitness $witnessPath -ErrorAction Stop # Set file share witness.
    }
    $module.Result.changed = $true
  }
} catch {
  $module.FailJson($_.Exception.Message)
}
$module.ExitJson()
