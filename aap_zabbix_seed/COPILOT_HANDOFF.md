# Copilot development instructions

You are extending an existing enterprise Ansible AAP → Zabbix KPI POC. Read README.md and source files before editing. **Do not claim unexecuted tests passed.**

## Non-negotiable design
- Aggregate callback, final recap publication only.
- Use existing AAP job metadata and domain extra variable.
- Fixed inventory → environment mapping; default deny unapproved jobs.
- Stable master trapper key per automation/environment/domain.
- Zabbix API failures never fail Ansible.
- No Controller API calls, per-host persistence, stdout capture, extra services, or secret logging.
- Avoid unsupported Ansible internals unless proven against installed EE version.

## Task order
1. Run `ansible --version` in the real AAP EE and test metadata access in `v2_playbook_on_play_start`. Show actual logs and prove it precedes fact gathering. If unsupported, identify a version-appropriate supported mechanism and write a regression test.
2. Validate Zabbix 7.x `history.push` against a test trapper item. Record real response and errors.
3. Implement separate **idempotent** item provisioning, first master, then dependent numeric items, after verifying exact API schema.
4. Test multi-play runs, repeated executions, unknown context, token errors, unreachable hosts.
5. Validate calendar-day totals including reruns, missing jobs and history retention.
6. Only then package as Galaxy collection with EE install instructions.

## First Copilot prompt

Read README.md and COPILOT_HANDOFF.md. Start with the callback variable-access checkpoint. Inspect installed ansible-core and prove that awx_job_id, awx_job_template_name, awx_inventory_name and domain_id are accessible in v2_playbook_on_play_start, before gather_facts. Do not implement new architecture or Zabbix dashboards until this passes. Show actual test commands and output.
