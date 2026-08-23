Import-Module Ansible.Basic

$spec = @{
  options = @{
    cluster_name = @{ type = 'str'; required = $true }
    mode = @{ type = 'str'; required = $true }
    witness_path = @{ type = 'str'; required = $false }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

try {
  if (-not (Get-Module -ListAvailable -Name FailoverClusters)) {
    $module.FailJson('FailoverClusters PowerShell module is not available.')
  }

  Import-Module FailoverClusters -ErrorAction Stop

  $mode = $module.Params.mode
  $witnessPath = $module.Params.witness_path
  $fileWitnessModes = @('NodeAndFileShareMajority', 'FileShareWitness')

  if (($mode -ne 'NodeMajority') -and ($fileWitnessModes -notcontains $mode)) {
    $module.FailJson("Unsupported quorum mode '$mode'.")
  }

  $useFileWitness = $fileWitnessModes -contains $mode
  if ($useFileWitness -and [string]::IsNullOrWhiteSpace($witnessPath)) {
    $module.FailJson('witness_path is required for file share witness mode.')
  }

  $quorum = Get-ClusterQuorum -Cluster $module.Params.cluster_name -ErrorAction Stop
  $resource = $quorum.QuorumResource
  $currentPath = $null
  $isFileWitness = $false

  if ($null -ne $resource) {
    $isFileWitness = $resource.ResourceType -eq 'File Share Witness'
    if ($isFileWitness) {
      $currentPath = (Get-ClusterParameter -InputObject $resource -Name SharePath -ErrorAction SilentlyContinue).Value
    }
  }

  if ($useFileWitness) {
    $needsChange = (-not $isFileWitness) -or ($currentPath -ne $witnessPath)
  }
  else {
    $needsChange = $null -ne $resource
  }

  $module.Result.changed = $needsChange

  if (-not $needsChange -or $module.CheckMode) {
    $module.ExitJson()
  }

  if ($useFileWitness) {
    Set-ClusterQuorum -Cluster $module.Params.cluster_name -FileShareWitness $witnessPath -ErrorAction Stop | Out-Null
  }
  else {
    Set-ClusterQuorum -Cluster $module.Params.cluster_name -NoWitness -ErrorAction Stop | Out-Null
  }

  $module.ExitJson()
}
catch {
  $module.FailJson($_.Exception.Message)
}
