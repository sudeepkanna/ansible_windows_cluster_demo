# Implementation plan and release gates

| Stage | Deliverable | Acceptance gate |
| --- | --- | --- |
| 0 | Collection structure, mapping, pure KPI logic, unit tests | Unit tests pass |
| 1 | Callback metadata and lifecycle in actual AAP EE | `awx_*` + `domain_id` visible before gather_facts; no env substitution |
| 2 | Zabbix `history.push` and master trapper provisioning | One real JSON value in Latest data, failures nonfatal |
| 3 | Idempotent dependent numeric item provisioning | Values match JSONPath; repeated apply is safe |
| 4 | Optional selected task metrics | Only exact allowlisted numeric fields; no_log respected |
| 5 | Dashboard: platform/environment/domain/job | Daily and 30/90-day comparisons validated |
| 6 | Scheduled-job missing detection and rerun semantics | Expected-vs-reported rules documented and tested |
| 7 | AAP EE packaging, performance and resilience | Parallel jobs, API outage, multi-play, retention tested |
| 8 | Production release | Security, operations runbook, rollback and ownership signed off |

## Non-goals

No per-host Zabbix item, no full task/event storage, no Controller API polling, no separate aggregation database, no automatic retries that block AAP.

## Report output location

Save generated validation results in `reports/`, e.g. `reports/metadata-ee.md`, `reports/zabbix-api.md`, `reports/aggregation.md`. Do not commit secrets or unredacted logs.
