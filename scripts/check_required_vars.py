#!/usr/bin/env python3
"""Simple validation for required variables and inventory for this demo repo.

Checks:
- group_vars/windows_cluster_nodes.yml contains cluster_name (non-empty), cluster_ip (non-empty), cluster_nodes (list, len>=2)
- If quorum_mode requires a file share witness, quorum_witness_path exists and non-empty
- inventory/hosts.ini has at least two hosts under [windows_cluster_nodes]

Exit codes:
- 0 if all checks pass
- 1 if any check fails
"""
import sys
from pathlib import Path

try:
    import yaml
except Exception:
    print("Missing dependency: pyyaml. Install with 'pip install pyyaml'")
    sys.exit(2)

repo_root = Path(__file__).resolve().parents[1]
vars_file = repo_root / "group_vars" / "windows_cluster_nodes.yml"
inv_file = repo_root / "inventory" / "hosts.ini"

errors = []

if not vars_file.exists():
    errors.append(f"Missing vars file: {vars_file}")
else:
    data = yaml.safe_load(vars_file.read_text()) or {}
    # cluster_name: required string.
    if not data.get("cluster_name") or not isinstance(data.get("cluster_name"), str):
        errors.append("cluster_name must be set to a non-empty string in group_vars/windows_cluster_nodes.yml")
    # cluster_ip: required string.
    if not data.get("cluster_ip") or not isinstance(data.get("cluster_ip"), str):
        errors.append("cluster_ip must be set to a non-empty string in group_vars/windows_cluster_nodes.yml")
    # cluster_nodes: list with at least two entries.
    nodes = data.get("cluster_nodes")
    if not isinstance(nodes, list) or len(nodes) < 2:
        errors.append("cluster_nodes must be a list with at least two hostnames in group_vars/windows_cluster_nodes.yml")
    # quorum: witness path required for file share modes.
    qm = data.get("quorum_mode")
    if qm in ["NodeAndFileShareMajority", "FileShareWitness"]:
        wp = data.get("quorum_witness_path")
        if not wp or not isinstance(wp, str):
            errors.append("quorum_witness_path must be set (non-empty string) when quorum_mode requires a file share witness")

# inventory hosts count
if not inv_file.exists():
    errors.append(f"Missing inventory file: {inv_file}")
else:
    lines = [l.strip() for l in inv_file.read_text().splitlines()]
    host_section = False
    hosts = []
    for l in lines:
        if l.startswith("[") and l.endswith("]"):
            host_section = (l.strip() == "[windows_cluster_nodes]")
            continue
        if host_section and l and not l.startswith("#"):
            if "[" in l and "]" in l:
                # New section marker encountered.
                host_section = False
                continue
            hosts.append(l)
    if len(hosts) < 2:
        errors.append("inventory/hosts.ini must contain at least two hosts in the [windows_cluster_nodes] section")

if errors:
    print("Validation FAILED:\n")
    for e in errors:
        print(f" - {e}")
    sys.exit(1)

print("Validation succeeded — required variables and inventory look good.")
sys.exit(0)
