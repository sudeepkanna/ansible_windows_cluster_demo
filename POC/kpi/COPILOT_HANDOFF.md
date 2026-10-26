# Copilot engineering contract — read before editing

Work only within the `POC/kpi` VS Code workspace. The collection is `ansible_collections/enterprise/automation_kpi`; keep it a **real Galaxy collection**, not a standalone callback folder. Read README, docs/ARCHITECTURE.md, docs/ROADMAP.md, and source before changing anything.

## Engineering rules

1. No invented API fields, no assumed ansible-core behavior, no unexecuted test claims. Record commands, versions and output in `reports/`.
2. Use existing AAP job variables; resolve at play start. If `get_option()` or play variable-manager fallback fails, diagnose actual EE internals before choosing an approach. No Controller API query.
3. No per-host records or full task outputs. Only native recap counters and explicitly allowlisted numeric task fields. Respect `no_log`.
4. Only approved job/inventory/domain combinations publish. No API calls per task.
5. Zabbix API failures must not fail the play. Token only from secure environment injection.
6. Stable Zabbix master item per logical job; never create an item per execution.
7. Provision items and dashboards with separate idempotent scripts; callback only pushes values.
8. Keep test output under `reports/` and update ROADMAP acceptance gates as proven.
9. Never claim recap-derived job status equals authoritative AAP Controller status.
10. Confirm Zabbix daily graph/calendar aggregation, missing jobs, reruns and retention before production dashboard claims.

## First Copilot task

"Read COPILOT_HANDOFF.md, README.md, docs/ARCHITECTURE.md and docs/ROADMAP.md. Run unit tests. Then validate the callback's metadata resolution against the installed ansible-core version and actual AAP EE. Prove awx_job_id, awx_job_template_name, awx_inventory_name and domain_id resolve in v2_playbook_on_play_start before gather_facts. Do not start dashboards or dependent item provisioning until this is proven. Record actual commands, versions, logs and issues in reports/metadata-ee.md."
