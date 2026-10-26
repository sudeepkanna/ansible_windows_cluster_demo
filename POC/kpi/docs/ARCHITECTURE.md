# Architecture and data contract

## Execution boundary

AAP injects `awx_job_id`, `awx_job_template_name`, `awx_inventory_name`; `domain_id` is an extra var. At `v2_playbook_on_play_start` resolve context **once** and default-deny unknown combinations. The callback's variable-access methods are compatibility probes, not proven stable across ansible-core releases.

At task callbacks, optionally sum allowlisted numeric fields by exact task name. Never store full task result, stdout, secrets, or per-host events. At `v2_playbook_on_stats`, derive final recap counters, form one compact JSON document and call Zabbix `history.push` once. Network errors must never affect playbook outcome.

## Payload example (illustrative, not measured)

```json
{"schema_version":1,"job_id":12540,"job_name":"Windows Desired State","inventory":"Windows Production","automation":"desired_state","environment":"prod","domain":"domain_a","completed_at":"2026-10-24T06:15:00+00:00","duration_seconds":1850,"recap_status":"failed","hosts":{"passed":492,"failed":5,"unreachable":3},"tasks":{"ok":12000,"changed":350,"failures":5,"unreachable":3,"skipped":1800,"rescued":0,"ignored":0},"selected":{}}
```

The example is illustrative; the `failed` status is consistent with nonzero failed/unreachable hosts under the implemented recap-based rule.

## Zabbix item plan

One master Text trapper per logical combination, e.g. `aap.job.raw[desired_state,prod,domain_a]`. Planned dependent items:

| Numeric key prefix | JSONPath |
| --- | --- |
| `aap.hosts.passed` | `$.hosts.passed` |
| `aap.hosts.failed` | `$.hosts.failed` |
| `aap.hosts.unreachable` | `$.hosts.unreachable` |
| `aap.tasks.ok` | `$.tasks.ok` |
| `aap.tasks.changed` | `$.tasks.changed` |
| `aap.tasks.failures` | `$.tasks.failures` |
| `aap.tasks.skipped` | `$.tasks.skipped` |
| `aap.duration` | `$.duration_seconds` |
| `aap.job.success` | `$.recap_status` → JS map success to 1 |

Provisioning of dependent items must use the live-verified Zabbix 7.x API schema and remain separate from callback execution.

## Reporting windows

Do not conflate rolling 24-hour sums, midnight-aligned calendar days, latest values and scheduled-job completion. Validate graph widget sum aggregation and history/trend retention with repeated executions and missing jobs. A missed callback publication cannot be detected by execution history alone without an expected schedule contract.
