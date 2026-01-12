Contributing & Testing

Thanks for contributing! This repository includes a small automated check to validate required configuration variables and inventory.

Local quick tests

1. Create and activate a Python virtualenv (recommended):

   python -m venv .venv && source .venv/bin/activate

2. Install the test deps:

   pip install -r requirements-dev.txt

3. Run the validator:

   python scripts/check_required_vars.py

This script checks `group_vars/windows_cluster_nodes.yml` for required keys (cluster_name, cluster_ip, cluster_nodes, quorum settings) and ensures `inventory/hosts.ini` contains at least two hosts in the `[windows_cluster_nodes]` group.

CI

A GitHub Actions workflow is provided (`.github/workflows/ci.yml`) to run the validator on pushes and pull requests.

Contributions

- Feature additions, documentation improvements, and tests are welcome.
- Please open a PR with a short description and include test / validation updates where relevant.
