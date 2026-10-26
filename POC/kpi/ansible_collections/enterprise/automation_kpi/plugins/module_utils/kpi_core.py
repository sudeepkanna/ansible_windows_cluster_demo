"""Pure business rules. No Ansible, network, or logging dependencies."""
import json
import re
from datetime import datetime, timezone

SAFE = re.compile(r"^[A-Za-z0-9_.-]+$")
COUNTERS = ("ok", "changed", "failures", "unreachable", "skipped", "rescued", "ignored")

def classify(config, meta):
    policy = config["reporting"]
    if not policy.get("enabled", False):
        return None
    job = policy.get("jobs", {}).get(str(meta.get("awx_job_template_name") or ""))
    env = policy.get("inventories", {}).get(str(meta.get("awx_inventory_name") or ""))
    domain = str(meta.get("domain_id") or "").lower()
    if not job or not env or domain not in policy.get("allowed_domains", []):
        return None
    if not all(SAFE.fullmatch(str(v)) for v in (job, env, domain)):
        return None
    return {"automation": job, "environment": env, "domain": domain}

def item_key(config, context):
    prefix = config.get("zabbix", {}).get("key_prefix", "aap.job.raw")
    if not SAFE.fullmatch(prefix):
        raise ValueError("Invalid Zabbix key prefix")
    return f'{prefix}[{context["automation"]},{context["environment"]},{context["domain"]}]'

def summarize(stats):
    totals = {k: 0 for k in COUNTERS}
    hosts = {"passed": 0, "failed": 0, "unreachable": 0}
    for hostname in stats.processed:
        result = stats.summarize(hostname)
        for k in COUNTERS:
            totals[k] += int(result.get(k, 0))
        if result.get("unreachable", 0):
            hosts["unreachable"] += 1
        elif result.get("failures", 0):
            hosts["failed"] += 1
        else:
            hosts["passed"] += 1
    return hosts, totals

def create_payload(meta, context, stats, elapsed, selected=None):
    hosts, tasks = summarize(stats)
    job_id = int(meta["awx_job_id"])
    if job_id <= 0:
        raise ValueError("Invalid AAP job ID")
    return {"schema_version": 1, "job_id": job_id,
            "job_name": str(meta["awx_job_template_name"]),
            "inventory": str(meta["awx_inventory_name"]),
            **context, "completed_at": datetime.now(timezone.utc).isoformat(),
            "duration_seconds": round(max(0.0, elapsed), 3),
            # Derived recap status; NOT authoritative AAP Controller job status.
            "recap_status": "failed" if hosts["failed"] or hosts["unreachable"] else "successful",
            "hosts": hosts, "tasks": tasks, "selected": selected or {}}

def extract_selected(result, rules, selected):
    """Opt-in extraction of scalar allowlisted result fields; no full result storage."""
    task = result._task
    name = task.get_name()
    rule = rules.get(name)
    if not rule or getattr(task, 'no_log', False):
        return
    data = result._result
    if data.get('_ansible_no_log'):
        return
    fields = rule.get('fields', [])
    if not isinstance(fields, list) or len(fields) > 8:
        return
    item = selected.setdefault(name, {})
    for field in fields:
        if field in data and isinstance(data[field], (bool, int, float)):
            # Numeric aggregate only: count booleans, sum numeric fields.
            item[field] = item.get(field, 0) + int(data[field]) if isinstance(data[field], bool) else item.get(field, 0) + data[field]

def encode(data):
    return json.dumps(data, separators=(',', ':'), sort_keys=True)
