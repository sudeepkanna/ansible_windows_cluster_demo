Import-Module Ansible.Basic

$spec = @{
  options = @{
    name = @{ type = 'str'; required = $true }
    nodes = @{ type = 'list'; elements = 'str'; required = $true }
    static_address = @{ type = 'str'; required = $true }
  }
  supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

function Normalize-NodeName($name) {
  return (($name -split '\.')[0]).ToLowerInvariant()
}

try {
  if (-not (Get-Module -ListAvailable -Name FailoverClusters)) {
    $module.FailJson('FailoverClusters PowerShell module is not available.')
  }

  Import-Module FailoverClusters -ErrorAction Stop
  $cluster = Get-Cluster -Name $module.Params.name -ErrorAction SilentlyContinue

  if ($null -ne $cluster) {
    $currentNodes = @(Get-ClusterNode -Cluster $module.Params.name | ForEach-Object { Normalize-NodeName $_.Name } | Sort-Object -Unique)
    $desiredNodes = @($module.Params.nodes | ForEach-Object { Normalize-NodeName $_ } | Sort-Object -Unique)

    $currentIps = @(
      Get-ClusterResource -Cluster $module.Params.name |
        Where-Object ResourceType -eq 'IP Address' |
        ForEach-Object {
          (Get-ClusterParameter -InputObject $_ -Name Address -ErrorAction SilentlyContinue).Value
        } |
        Where-Object { $_ }
    )

    if (Compare-Object $currentNodes $desiredNodes) {
      $module.FailJson("Cluster exists but node membership does not match. Current: $($currentNodes -join ', ')")
    }

    if ($currentIps -notcontains $module.Params.static_address) {
      $module.FailJson("Cluster exists but static IP does not match. Current: $($currentIps -join ', ')")
    }

    $module.Result.exists = $true
    $module.Result.changed = $false
    $module.ExitJson()
  }

  $module.Result.changed = $true
  $module.Result.exists = $false

  if ($module.CheckMode) {
    $module.ExitJson()
  }

  New-Cluster -Name $module.Params.name -Node $module.Params.nodes -StaticAddress $module.Params.static_address -NoStorage -ErrorAction Stop | Out-Null
  $module.Result.exists = $true
  $module.ExitJson()
}
catch {
  $module.FailJson($_.Exception.Message)
}
