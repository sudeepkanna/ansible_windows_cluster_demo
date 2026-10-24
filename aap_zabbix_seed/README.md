# AAP → Zabbix KPI — enterprise POC seed

## Purpose

This repository is a **working starting point**, not a production-certified solution. It demonstrates a nonfatal Ansible aggregate callback, context allowlisting, native recap counters and Zabbix `history.push`. It does not require Controller API calls or changes to existing AAP playbooks.

**First checkpoint:** prove `awx_job_id`, `awx_job_template_name`, `awx_inventory_name`, and `domain_id` resolve in the callback's `v2_playbook_on_play_start` **inside your actual AAP execution environment**. The callback checks plugin variable-backed options, then version-dependent play variable-manager access. Neither is claimed verified against your EE. A local environment-variable diagnostic fallback exists only when explicitly enabled.

## Quick start in VS Code / WSL

```bash
cd aap_zabbix_seed
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
ansible --version
ansible-doc -t callback aap_zabbix_kpi
export AAP_ZABBIX_CONFIG="$PWD/config/reporting.yml"
ansible-playbook -i examples/inventory.ini examples/test_playbook.yml \
  -e awx_job_id=12540 \
  -e 'awx_job_template_name=Windows Desired State' \
  -e 'awx_inventory_name=Windows Production' \
  -e domain_id=domain_a
```

The local test **must** show a `AAP_ZABBIX_KPI: context_source=...` message and approved metadata. If it shows unresolved context, stop: do not mask it with environment fallback. Repeat inside the EE with facts enabled and disabled.

## Configuration

Edit `config/reporting.yml` to use **your actual** AAP job template names, fixed inventory names, approved domain IDs and Zabbix URL. All names in this seed are placeholders.

## Zabbix test

1. Create an existing Zabbix technical host named `AAP-MONITORING` (or configure the actual technical host name).
2. Create a **Zabbix trapper** item with **Text** value type and key `aap.job.raw[desired_state,prod,domain_a]`. Host/item creation is manual in this seed.
3. Set `ZABBIX_API_TOKEN` securely in the test process. Never commit it.
4. Re-run the test playbook. Check `Monitoring → Latest data`.
5. Confirm actual `history.push` response and validate API token permissions. The callback never fails the play if Zabbix fails.
6. Create dependent numeric items with JSONPath `$.hosts.failed`, `$.hosts.passed`, `$.tasks.changed`, `$.tasks.failures`, `$.duration_seconds`. Do not assume these are already provisioned.

## Semantics

- Native Ansible `Stats.summarize(host)` values are aggregated once at final recap. `ok`, `changed`, `failures`, etc. count **task-host outcomes**, not distinct tasks.
- `hosts.passed` is based on hosts **present in the final recap** with no failure/unreachable count. It does not measure expected coverage.
- `status` is inferred from recap; it is **not authoritative AAP Controller status**.
- `duration_seconds` is elapsed time since callback initialization, not Controller queue or official job runtime.
- Each completed execution writes to the same stable logical item key. The job ID stays inside JSON.
- A forced termination may skip publication. Zabbix failures are nonfatal.
- No full task output, secrets, per-host history, background services, or extra Controller API calls.
- Missing job reporting, calendar-day aggregation, dependent-item provisioning and retention policy are **future test work**, not implemented features.

## Initial test acceptance criteria

1. Unit tests pass.
2. Callback loads with installed ansible-core.
3. Metadata appears before gather_facts, without environment fallback.
4. One completed playbook publishes one JSON value.
5. Unknown job/inventory/domain publishes nothing.
6. Invalid token or unreachable Zabbix does not change playbook result.
7. Multiple executions append history to one item.

## Known limitations

Ansible-core is not installed in the artifact-generation environment, so the callback lifecycle has **not** been integration-tested here. Confirm the `DOCUMENTATION` option schema, `get_option` behavior, and variable-manager access against your EE version. The `history.push` response validation likewise needs a live Zabbix 7.x test. Do not promote this seed to production without those checks.
