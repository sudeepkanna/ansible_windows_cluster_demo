
This demo repo shows:
- Role-based Windows Failover Cluster creation
- Custom PowerShell modules using Ansible.Basic
- Idempotent cluster & quorum logic
- Example Windows Action Plugin (controller-side)
- Sample inventory + group/host vars layout
- Preflight validation for cluster inputs
- Feature install, patching, build alignment, and Test-Cluster validation

Folders:
library/          -> PowerShell modules (run on Windows hosts)
plugins/action/   -> Action plugins (run on controller)
roles/            -> Orchestration & idempotence
inventory/        -> Sample inventory for Windows hosts
group_vars/       -> Group-level variables (cluster config)
host_vars/        -> Host-level overrides (optional)

Usage & Quickstart:

Prerequisites:
- Ansible 2.9+ installed (or your preferred version).
- Python virtualenv (recommended) and the ability to install packages (e.g., `pip install ansible pywinrm`).
- Windows hosts prepared for WinRM (set `ansible_connection=winrm` and proper auth).
- Ensure `inventory/hosts.ini` credentials and host IPs are updated.

Quickstart — full run (creates cluster + quorum):

1. Create a venv and install requirements (optional but recommended):

   python -m venv .venv && source .venv/bin/activate  # create and activate a Python virtualenv for local validation and optional Ansible runs
   pip install ansible pywinrm                         # install Ansible and WinRM dependencies (used if you want to run playbooks locally)

2. Edit `inventory/hosts.ini` and `group_vars/windows_cluster_nodes.yml` to match your environment (update `ansible_password`, `cluster_ip`, `cluster_nodes`, and quorum settings).  # inventory provides connection vars; group_vars define cluster variables used by the role (see Variables reference section)

3. Run the full playbook (idempotent):

   ansible-playbook -i inventory/hosts.ini site.yml  # runs `site.yml` which applies the `win_failover_cluster` role across `windows_cluster_nodes`; variables come from `group_vars/windows_cluster_nodes.yml`
   # Role flow: preflight, check cluster presence/membership; if missing, run TCP checks, install features, apply updates (optional), verify build alignment, run Test-Cluster (skip Storage), then create cluster and set quorum. If present, report quorum details and skip changes.
   # Full flow diagram: docs/flow.txt

Helpful focused commands (run specific action) — detailed explanations:

- Run preflight validations only:

  ansible-playbook -i inventory/hosts.ini playbooks/preflight.yml  # runs role validations (assertions) without changing hosts

  Explanation:
  - Calls: `playbooks/preflight.yml`, which includes `roles/win_failover_cluster/tasks/preflight.yml`.
  - Files/Tasks executed: `roles/win_failover_cluster/tasks/preflight.yml` (assertions and validations).
  - Variables validated: `cluster_name`, `cluster_ip`, `cluster_nodes`, `quorum_mode`, `quorum_witness_path`.
  - Conditions: quorum witness checks run only when `quorum_mode` is `NodeAndFileShareMajority` or `FileShareWitness` (see `when:` on the assertion).

- Create the cluster (runs the create logic on the primary node only):

  ansible-playbook -i inventory/hosts.ini playbooks/create_cluster.yml  # includes `roles/win_failover_cluster/tasks/create_cluster.yml` and runs create logic on `cluster_primary` only

  Explanation:
  - Calls: `playbooks/create_cluster.yml`, which includes `roles/win_failover_cluster/tasks/create_cluster.yml`.
  - Files/Tasks executed: `roles/win_failover_cluster/tasks/create_cluster.yml` (with fallback checks only).
  - Variables used: `cluster_name`, `cluster_nodes`, `cluster_ip`, and `cluster_primary` (set from `cluster_nodes | first` in `roles/win_failover_cluster/tasks/main.yml`).
  - Runtime behavior: `Check cluster state` uses `win_cluster_info` and runs only when `inventory_hostname == cluster_primary`.
    `Create cluster when missing` uses `win_cluster_create` and runs on the same condition plus `not cluster_present | bool` to avoid recreating an existing cluster.
  - Module outputs: `win_cluster_info` sets `exists`; `win_cluster_create` sets `changed` when it creates a cluster.

- Ensure quorum/witness is configured:

  ansible-playbook -i inventory/hosts.ini playbooks/quorum.yml  # runs quorum logic on `cluster_primary` and applies FileShare witness when needed

  Explanation:
  - Calls: `playbooks/quorum.yml`, which includes `roles/win_failover_cluster/tasks/quorum.yml`.
  - Files/Tasks executed: `roles/win_failover_cluster/tasks/quorum.yml`.
  - Variables used: `cluster_name`, `quorum_mode`, `quorum_witness_path`.
  - Runtime behavior: runs only on `cluster_primary` (`when: inventory_hostname == cluster_primary`). The PowerShell module compares the desired quorum to the current quorum and sets `changed` only when an update was needed.

- Get cluster info (runs once):

  ansible-playbook -i inventory/hosts.ini playbooks/cluster_info.yml  # runs a single `win_cluster_info` call (run_once) and prints the registered `cluster_info`

  Explanation:
  - Calls: `playbooks/cluster_info.yml`.
  - Tasks: runs `win_cluster_info` with `run_once: true` so it executes a single query and registers `cluster_info` for display.
  - Variables: reads `cluster_name` from `group_vars/windows_cluster_nodes.yml`.

- Run the controller-side action plugin example (runs on localhost):

  ansible-playbook -i inventory/hosts.ini playbooks/plugin_example.yml  # runs the `win_cluster_example` plugin on the controller and prints the returned `msg`

  Explanation:
  - Calls: `playbooks/plugin_example.yml` which runs the `win_cluster_example` action plugin on the controller (`hosts: localhost, connection: local`).
  - Purpose: demonstrates a controller-side plugin that sets a `msg` in the result.

Notes on command flags and safety:
- `--check`: dry-run (some modules may not support check mode fully; test cautiously).
- `-v` / `-vvv`: verbosity for debugging and viewing module returns.
- `--limit <host>`: restrict run to specific hosts (useful to test primary-only behavior).


Safety / Debugging tips:
- Use `--check` for a dry-run when safe: `ansible-playbook -i inventory/hosts.ini site.yml --check`.
- Use `-v` (verbose) to see more details.
- If a task needs to run on a single host, consider using `--limit <host>`.

Files of interest:

- `site.yml` — main playbook that includes the `win_failover_cluster` role.
- `playbooks/` — small playbooks for specific actions: `preflight.yml`, `create_cluster.yml`, `quorum.yml`, `cluster_info.yml`, `plugin_example.yml`.
- `roles/win_failover_cluster/tasks/` — contains `preflight.yml`, `cluster_state.yml`, `network.yml`, `features.yml`, `updates.yml`, `build_alignment.yml`, `validate_cluster.yml`, `create_cluster.yml`, `quorum.yml`, and `cluster_report.yml` task sets.
- `group_vars/windows_cluster_nodes.yml` — cluster configuration (name, IP, nodes, quorum settings).
- `inventory/hosts.ini` — sample inventory + WinRM connection variables (ansible_host, ansible_user, ansible_password, ansible_connection, ansible_winrm_transport, ansible_winrm_server_cert_validation).
- `host_vars/*` — optional per-host overrides (e.g., `ansible_host` or host-specific variables).
- `library/*.ps1` — PowerShell Ansible modules executed on Windows hosts (`win_cluster_create`, `win_cluster_info`, `win_cluster_membership_info`, `win_cluster_port_check`, `win_cluster_quorum_info`, `win_cluster_quorum_ensure`, `win_cluster_module_check`, `win_cluster_build_info`, `win_cluster_validate`, `win_cluster_ensure`).
- `plugins/action/win_cluster_example.py` — example controller-side Action plugin.
- `scripts/check_required_vars.py` — local validator that ensures required variables and inventory entries exist (used by the test target / CI).

Variables reference & where used:

- `cluster_name` — defined in `group_vars/windows_cluster_nodes.yml` (defaults in `roles/win_failover_cluster/defaults/main.yml`). Used by `roles/win_failover_cluster/tasks/create_cluster.yml`, `roles/win_failover_cluster/tasks/quorum.yml`, and `playbooks/cluster_info.yml` to target cluster modules.
- `cluster_ip` — defined in `group_vars/windows_cluster_nodes.yml` (defaults in `roles/win_failover_cluster/defaults/main.yml`). Passed as `static_address` to the `win_cluster_create` module.
- `cluster_nodes` — defined in `group_vars/windows_cluster_nodes.yml` (defaults in `roles/win_failover_cluster/defaults/main.yml`, with `groups['windows_cluster_nodes']` if undefined). Used to compute `cluster_primary` (`{{ cluster_nodes | first }}`) and passed to `win_cluster_create`.
- `cluster_primary` — derived in `roles/win_failover_cluster/tasks/main.yml` using `set_fact`. Many tasks use `when: inventory_hostname == cluster_primary` to run primary-only operations.
- `quorum_mode` — defined in `group_vars/windows_cluster_nodes.yml` (default in `roles/win_failover_cluster/defaults/main.yml`). Passed into the `win_cluster_quorum_ensure` module and used by preflight assertions to determine if `quorum_witness_path` is required.
- `quorum_witness_path` — defined in `group_vars/windows_cluster_nodes.yml` (default in `roles/win_failover_cluster/defaults/main.yml`) when using a file share witness. Validated in `roles/win_failover_cluster/tasks/preflight.yml` when `quorum_mode` requires it.
- `cluster_features` — defined in `roles/win_failover_cluster/defaults/main.yml`. Feature list used by `roles/win_failover_cluster/tasks/features.yml` to install Failover Clustering prerequisites.
- `cluster_ps_module` — defined in `roles/win_failover_cluster/defaults/main.yml`. PowerShell module name used by `roles/win_failover_cluster/tasks/features.yml` and the PowerShell modules under `library/`.
- `cluster_feature_reboot` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `true`: reboot automatically when feature install requires it; set to `false` to stop and let the operator reboot). Used in `roles/win_failover_cluster/tasks/features.yml`.
- `cluster_feature_reboot_timeout` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `3600` seconds). Used in `roles/win_failover_cluster/tasks/features.yml`.
- `cluster_update_enabled` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `true`: install updates; set to `false` to skip). Used in `roles/win_failover_cluster/tasks/updates.yml`.
- `cluster_update_categories` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `CriticalUpdates`, `SecurityUpdates`, `UpdateRollups`). Passed to `win_updates` in `roles/win_failover_cluster/tasks/updates.yml`.
- `cluster_update_reboot` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `true`: auto-reboot when required; set to `false` to leave reboot to operator). Passed to `win_updates` in `roles/win_failover_cluster/tasks/updates.yml`.
- `cluster_update_reboot_timeout` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `3600` seconds). Passed to `win_updates` in `roles/win_failover_cluster/tasks/updates.yml`.
- `cluster_allow_registry_fallback` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `true`: allow registry-based membership detection when the module is missing). Used in `roles/win_failover_cluster/tasks/cluster_state.yml`.
- `cluster_network_check_enabled` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `true`: check TCP ports between nodes; set to `false` to skip). Used in `roles/win_failover_cluster/tasks/network.yml`.
- `cluster_network_ports` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `135, 445, 3343`: TCP ports to check). Used in `roles/win_failover_cluster/tasks/network.yml`.
- `cluster_network_timeout_seconds` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `3`: per-port timeout). Used in `roles/win_failover_cluster/tasks/network.yml`.
- `cluster_network_check_retries` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `2`: retry attempts per port). Used in `roles/win_failover_cluster/tasks/network.yml`.
- `cluster_network_check_delay_seconds` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `1`: delay between retries). Used in `roles/win_failover_cluster/tasks/network.yml`.
- `cluster_validation_enabled` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `true`: run `Test-Cluster`; set to `false` to skip). Used in `roles/win_failover_cluster/tasks/validate_cluster.yml`.
- `cluster_validation_include` — defined in `roles/win_failover_cluster/defaults/main.yml` (default empty: run all tests except those in `cluster_validation_skip`). Passed to `Test-Cluster` in `roles/win_failover_cluster/tasks/validate_cluster.yml`.
- `cluster_validation_skip` — defined in `roles/win_failover_cluster/defaults/main.yml` (default `Storage`: skip storage validation). Passed to `Test-Cluster` in `roles/win_failover_cluster/tasks/validate_cluster.yml`.
- `ansible_*` connection vars (e.g., `ansible_host`, `ansible_connection`, `ansible_user`, `ansible_password`) — defined in `inventory/hosts.ini` or `host_vars/*` and are used by Ansible for WinRM connectivity.

Examples & sample outputs 💡

- Dry-run (hint: some PowerShell modules may not fully support check mode):

  ansible-playbook -i inventory/hosts.ini site.yml --check -v  # dry-run: shows what would change; some modules may not support check mode fully

  Expected: Ansible will show which tasks would change; PowerShell modules might still report no change for checks.

- Run preflight with verbose output (shows assertions and their results):

  ansible-playbook -i inventory/hosts.ini playbooks/preflight.yml -v  # verbose preflight checks; fails fast if variables are missing/invalid

  Expected (satifying config): tasks pass without failing assertions.

- Create cluster with verbose logs (primary-only actions are visible):

  ansible-playbook -i inventory/hosts.ini playbooks/create_cluster.yml -vv  # verbose create run; shows primary-only behavior and module returns

  Expected snippets:
  - The `Check cluster state` task runs on the host equal to `cluster_primary`.
  - If `cluster_present` is false, `Create cluster when missing` runs and shows `changed: true` when the cluster is created.

- Run the controller plugin example (local):

  ansible-playbook -i inventory/hosts.ini playbooks/plugin_example.yml  # runs locally on the controller; useful to verify controller-side plugins

  Expected output:
  - The plugin will set `msg: Action plugin executed on controller` and it will be printed by the `debug` task.

Testing & CI 🧪

- Local validator (macOS / Linux):

  # Ensure Python 3 is installed (use `python3 --version`). Install via Homebrew if missing: `brew install python`.
  python3 -m venv .venv && source .venv/bin/activate   # create + activate a Python 3 venv (zsh/bash)
  python -m pip install --upgrade pip                  # upgrade the venv's pip
  python -m pip install -r requirements-dev.txt        # install validator deps (pyyaml) into the venv
  python scripts/check_required_vars.py                # run the repository validator (uses the venv's Python)

  # Troubleshooting:
  # - If `python3` is not found, install Python 3 (Homebrew: `brew install python` or use `pyenv`).
  # - Use `python3` explicitly because `python` on macOS may point to Python 2 or be absent.
  # - If you prefer, run `python3 scripts/check_required_vars.py` directly without a venv, but using a venv is recommended for reproducible dev environments.

- `Makefile` target:

  make test  # runs `python3 scripts/check_required_vars.py` (same validator as above)

- GitHub Actions:

  A workflow (`.github/workflows/ci.yml`) runs the validator on push and pull requests (CI installs Python to run the same script).

Notes:
- The validator focuses on presence and basic structure of required configuration; it does not connect to Windows hosts.
- For AWX/Tower, use the `awx/awx_manifest.yml` and packaging helper (`make awx-package`) to assemble the set of files you want to publish to AWX.
- If you prefer visually marking folders for AWX, we can rename or add `-AWX` suffixed folders (example: `playbooks-AWX`) — tell me which convention you prefer.
- Contributions that add further test coverage (integration tests, molecule roles, or WinRM test harness) are welcome.

Notes:
- The role is idempotent: re-running the playbook won't recreate an existing cluster.
- When the cluster already exists, the role reports quorum details and skips network checks, feature installs, updates, Test-Cluster, creation, and quorum changes.
- If any node is already a member of a different cluster, the role fails before attempting creation.
- The role validates that every entry in `cluster_nodes` exists in the `windows_cluster_nodes` inventory group to avoid delegate failures.
- When the FailoverClusters module is missing, the role can use a registry fallback for membership detection (disable via `cluster_allow_registry_fallback`).
- `win_cluster_*` PowerShell modules use `Ansible.Basic` to report `changed`/`exists` back to Ansible.

Contributions:
- Feel free to add tests, CI, or additional playbooks for common workflows.

```
