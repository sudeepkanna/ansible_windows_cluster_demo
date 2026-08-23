# win_cluster_quorum_ensure.ps1
# Purpose: Ensure the cluster quorum configuration matches the desired mode and witness path.

Import-Module Ansible.Basic

$spec = @{
  options = @{
    cluster_name = @{ type = "str"; required = $true }
    mode = @{ type = "str"; required = $true }
    witness_path = @{ type = "str"; required = $false }
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

  $mode = $module.Params.mode
  $witnessPath = $module.Params.witness_path
  $allowedModes = @("NodeMajority", "NodeAndFileShareMajority", "FileShareWitness")

  if (-not ($allowedModes -contains $mode)) {
    $module.FailJson("Unsupported quorum mode '$mode'. Supported modes: " + ($allowedModes -join ", "))
  }

  $wantsFileShareWitness = $mode -in @("NodeAndFileShareMajority", "FileShareWitness")

  if ($wantsFileShareWitness -and [string]::IsNullOrWhiteSpace($witnessPath)) {
    $module.FailJson("witness_path must be set when quorum mode requires a file share witness.")
  }

  $q = Get-ClusterQuorum -Cluster $module.Params.cluster_name -ErrorAction Stop

  $currentShare = $null
  if ($null -ne $q.QuorumResource) {
    try {
      $currentShare = (Get-ClusterParameter -InputObject $q.QuorumResource -Name SharePath -ErrorAction Stop).Value
    }
    catch {
      $currentShare = $null
    }
  }

  # Do not depend on QuorumType text because its value varies by Windows Server version.
  # Instead, inspect the presence/type of the witness resource and its SharePath.
  if ($wantsFileShareWitness) {
    $needsChange = ($null -eq $q.QuorumResource) -or ($currentShare -ne $witnessPath)
  }
  else {
    # Node majority means no witness resource should be configured.
    $needsChange = $null -ne $q.QuorumResource
  }

  $module.Result.current_witness_path = $currentShare
  $module.Result.desired_witness_path = if ($wantsFileShareWitness) { $witnessPath } else { $null }
  $module.Result.changed = $needsChange

  if ($needsChange -and -not $module.CheckMode) {
    if ($wantsFileShareWitness) {
      # -FileShareWitness is the canonical parameter; -NodeAndFileShareMajority is an alias.
      Set-ClusterQuorum -Cluster $module.Params.cluster_name -FileShareWitness $witnessPath -ErrorAction Stop | Out-Null
    }
    else {
      Set-ClusterQuorum -Cluster $module.Params.cluster_name -NoWitness -ErrorAction Stop | Out-Null
    }
  }

  $module.ExitJson()
}
catch {
  $module.FailJson($_.Exception.Message)
}
