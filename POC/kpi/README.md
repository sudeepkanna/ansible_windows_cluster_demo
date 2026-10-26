# AAP → Zabbix KPI — Collection-first development workspace

**Workspace path:** `POC/kpi` (open this folder in VS Code). **Collection FQCN:** `enterprise.automation_kpi` (namespace is a placeholder you can rename). This is an engineering seed, **not production-certified**.

## Architecture

AAP job → `enterprise.automation_kpi.kpi` aggregate callback → approved job/inventory/domain metadata → native recap + allowlisted numeric task results → one `history.push` JSON value → stable Zabbix trapper master item → dependent numeric items → calculated metrics / native dashboards.

**No** Controller API queries, per-host event persistence, additional databases, message brokers or playbook modifications.

## Folder ownership

- `ansible_collections/enterprise/automation_kpi/`: production-target Galaxy collection source.
- `config/reporting.yml`: job allowlist, inventory/environment mapping, domains, selected task fields, Zabbix endpoint.
- `examples/`: safe localhost playbook for callback lifecycle tests.
- `scripts/`: Zabbix API probe and **master-only** item provisioning.
- `tests/`: pure Python unit tests.
- `reports/`: generated test reports, validation evidence and logs; never commit tokens.
- `docs/`: architecture, acceptance criteria and implementation roadmap.

## Local setup (WSL)

```bash
cd POC/kpi
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
python -m unittest discover -s tests -v
ansible --version
ansible-doc -t callback enterprise.automation_kpi.kpi
export AAP_KPI_CONFIG="$PWD/config/reporting.yml"
ansible-playbook -i examples/inventory.ini examples/test_playbook.yml \
  -e awx_job_id=12540 \
  -e 'awx_job_template_name=Windows Desired State' \
  -e 'awx_inventory_name=Windows Production' \
  -e domain_id=domain_a
```

Expected first checkpoint: `AAP_KPI: metadata source: ...` and `approved=True` **before any fact-gathering task**. Do not assume callback options or `play.get_variable_manager()` work in your EE; prove it there. Local test should work without a Zabbix token and skip publication.

## Zabbix

Configure an **existing** Zabbix technical host, API URL and approved job mappings in `config/reporting.yml`. Set `ZABBIX_API_TOKEN` using secure credential injection, never in Git.

```bash
python scripts/test_api.py
python scripts/provision_master.py            # dry-run
python scripts/provision_master.py --apply    # creates only missing master trapper items
```

Master item: trapper, Text, key `aap.job.raw[desired_state,prod,domain_a]`. `history.push` appends one JSON value per completed run. The callback is fail-open for reporting errors. Dependent items and dashboards are deliberately separate follow-on implementation tasks; see `docs/ROADMAP.md`.

## Semantics and constraints

- `hosts.passed/failed/unreachable`: final recap classification of hosts actually processed, **not unique intended fleet coverage**.
- `tasks.ok/changed/failures/...`: sums of Ansible per-host recap counters, not unique task names.
- `recap_status`: derived from recap, **not** authoritative Controller final job status.
- `duration_seconds`: callback-observed elapsed time, **not** Controller queue time.
- `selected`: numeric scalar fields only, aggregated by **exact task name**. Same-name tasks will be combined; tighten identity matching before production.
- Forced termination may not invoke final stats; missing record is acceptable by design.
- Multiple plays publish once, at final recap.
- Missing jobs, reruns, daily calendar boundaries and long-term retention need explicit tests before dashboard sign-off.

## Mandatory pre-production checks

1. Actual EE ansible-core version, callback plugin loading and variable access at play start.
2. `gather_facts: false` and `true`; custom `domain_id` supplied as AAP extra var.
3. Real Zabbix 7.x JSON-RPC `history.push` response and API permissions.
4. Native dependent items and daily aggregation with reruns/missing executions.
5. Parallel job completion, API outage, no-log and selected-task behavior.
6. Package with `ansible-galaxy collection build ansible_collections/enterprise/automation_kpi` and test EE installation.

**Do not claim these are passed until actual integration evidence is collected.**
