# win_cluster_validate.ps1
# Purpose: Run Test-Cluster with optional include/skip lists.
# Parameters:
# - nodes (list[str], required)
# - include (list[str], optional)
# - skip (list[str], optional)
# - module_name (str, optional, default: FailoverClusters)
# Outputs:
# - succeeded
# - report_file

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{
  nodes=@{type="list";elements="str";required=$true}
  include=@{type="list";elements="str";required=$false;default=@()}
  skip=@{type="list";elements="str";required=$false;default=@()}
  module_name=@{type="str";required=$false;default="FailoverClusters"}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.

try {
  $moduleName = $module.Params.module_name
  # Ensure the FailoverClusters module is available before Test-Cluster.
  if (-not (Get-Module -ListAvailable -Name $moduleName)) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure Failover Clustering features are installed.")
  }
  Import-Module $moduleName -ErrorAction Stop

  $nodes = $module.Params.nodes
  $include = $module.Params.include
  $skip = $module.Params.skip

  if ($include -and $include.Count -gt 0) {
    $result = Test-Cluster -Node $nodes -Include $include -Skip $skip -WarningAction SilentlyContinue -ErrorAction Stop
  } else {
    $result = Test-Cluster -Node $nodes -Skip $skip -WarningAction SilentlyContinue -ErrorAction Stop
  }

  if (-not $result.Succeeded) {
    $module.FailJson("Cluster validation failed. Review the Test-Cluster report for details.")
  }

  $module.Result.succeeded = [bool]$result.Succeeded
  $module.Result.report_file = $result.ReportFile
  $module.Result.changed = $false
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
