# win_cluster_port_check.ps1
# Purpose: Check TCP connectivity from the local node to peer nodes on required ports.
# Parameters:
# - nodes (list[str], required): Cluster node list.
# - ports (list[int], required): TCP ports to test.
# - local_node (str, required): Local node name to exclude from targets.
# - timeout_seconds (int, optional): Timeout per port check (default: 3).
# - retries (int, optional): Retry attempts per port (default: 2).
# - delay_seconds (int, optional): Delay between retries (default: 1).
# Outputs:
# - ok: true when all checks succeed
# - failures: list of failed target/port pairs

Import-Module Ansible.Basic # Load Ansible module helper.
$spec = @{ options = @{
  nodes=@{type="list";elements="str";required=$true}
  ports=@{type="list";elements="int";required=$true}
  local_node=@{type="str";required=$true}
  timeout_seconds=@{type="int";required=$false;default=3}
  retries=@{type="int";required=$false;default=2}
  delay_seconds=@{type="int";required=$false;default=1}
}}
$module = [Ansible.Basic.AnsibleModule]::Create($args,$spec) # Parse arguments.

try {
  $nodes = $module.Params.nodes
  $ports = $module.Params.ports
  $localNode = $module.Params.local_node
  $timeoutSeconds = [int]$module.Params.timeout_seconds
  $retries = [int]$module.Params.retries
  $delaySeconds = [int]$module.Params.delay_seconds

  if (-not $nodes -or $nodes.Count -lt 2) {
    $module.FailJson("nodes must include at least two entries to perform peer checks.")
  }
  if (-not $ports -or $ports.Count -lt 1) {
    $module.FailJson("ports must include at least one TCP port to check.")
  }

  $targets = $nodes | Where-Object { $_ -ne $localNode }
  $failures = @()

  $timeoutMs = $timeoutSeconds * 1000 # Convert seconds to milliseconds for socket timeout.
  foreach ($target in $targets) {
    foreach ($port in $ports) {
      $attempt = 0
      $success = $false
      while ($attempt -le $retries -and -not $success) {
        $attempt++
        $client = New-Object System.Net.Sockets.TcpClient # Use a direct socket check for predictable timing.
        try {
          $async = $client.BeginConnect($target, $port, $null, $null)
          $connected = $async.AsyncWaitHandle.WaitOne($timeoutMs, $false)
          if ($connected -and $client.Connected) {
            $client.EndConnect($async)
            $success = $true
          }
        } catch {
          $success = $false
        } finally {
          $client.Close()
        }
        if (-not $success -and $attempt -le $retries) {
          Start-Sleep -Seconds $delaySeconds
        }
      }
      if (-not $success) {
        $failures += [PSCustomObject]@{
          target = $target
          port = $port
        }
      }
    }
  }

  $module.Result.ok = ($failures.Count -eq 0)
  $module.Result.failures = $failures
  $module.Result.changed = $false
  $module.ExitJson()
} catch {
  $module.FailJson($_.Exception.Message)
}
