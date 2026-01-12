# win_cluster_module_check.ps1
# Purpose: Ensure a PowerShell module is available and optionally import it.
# Parameters:
# - module_name (str, required): Module name to check/import
# - import (bool, optional): Import the module when true (default: true)
# Outputs:
# - module_name: Name of the module checked
# - module_version: Highest available module version
# - imported: true when module was imported in this session

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{
  module_name=@{type="str";required=$true}
  import=@{type="bool";required=$false;default=$true}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.

try {
  $moduleName = $module.Params.module_name
  $importModule = $module.Params.import

  $available = Get-Module -ListAvailable -Name $moduleName # Check installed modules.
  if (-not $available) {
    $module.FailJson("PowerShell module '$moduleName' not found. Ensure required Windows features are installed.")
  }

  if ($importModule) {
    Import-Module $moduleName -ErrorAction Stop # Load module into session for downstream commands.
  }

  # Report the highest available version for visibility in logs.
  $module.Result.module_name = $moduleName
  $module.Result.module_version = ($available | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()
  $module.Result.imported = [bool]$importModule
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
