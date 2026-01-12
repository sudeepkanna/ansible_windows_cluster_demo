# win_cluster_build_info.ps1
# Purpose: Return Windows build information for alignment checks.
# Parameters: none
# Outputs:
# - build_number
# - ubr
# - display_version

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{} }
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # No parameters for this module.

try {
  $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' # Read OS build metadata.
  $module.Result.build_number = $cv.CurrentBuildNumber
  $module.Result.ubr = $cv.UBR
  $module.Result.display_version = $cv.DisplayVersion
  $module.Result.changed = $false
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
