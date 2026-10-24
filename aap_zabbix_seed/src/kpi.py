import json
import re
import ssl
import urllib.request
from datetime import datetime, timezone

SAFE = re.compile(r"^[a-zA-Z0-9_.-]+$")

def classify(config, metadata):
    r = config["reporting"]
    if not r.get("enabled", False):
        return None
    job = r["jobs"].get(str(metadata.get("awx_job_template_name", "")))
    env = r["inventories"].get(str(metadata.get("awx_inventory_name", "")))
    domain = str(metadata.get("domain_id") or "").lower()
    if not job or not env or domain not in r["allowed_domains"]:
        return None
    if not all(SAFE.fullmatch(v) for v in (job, env, domain)):
        return None
    return {"automation": job, "environment": env, "domain": domain}

def key_for(c):
    return "aap.job.raw[{automation},{environment},{domain}]".format(**c)

def recap(stats):
    counters = ("ok", "changed", "failures", "unreachable", "skipped", "rescued", "ignored")
    tasks = {k: 0 for k in counters}
    hosts = {"passed": 0, "failed": 0, "unreachable": 0}
    for hostname in stats.processed:
        s = stats.summarize(hostname)
        for k in counters:
            tasks[k] += int(s.get(k, 0))
        if int(s.get("unreachable", 0)):
            hosts["unreachable"] += 1
        elif int(s.get("failures", 0)):
            hosts["failed"] += 1
        else:
            hosts["passed"] += 1
    return hosts, tasks

def payload(metadata, classification, stats, duration):
    hosts, tasks = recap(stats)
    job_id = int(metadata["awx_job_id"])
    if job_id <= 0:
        raise ValueError("Invalid job ID")
    return {
        "schema_version": 1, "job_id": job_id,
        "job_name": str(metadata["awx_job_template_name"]),
        "inventory": str(metadata["awx_inventory_name"]),
        **classification,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "duration_seconds": round(max(0, duration), 3),
        "status": "failed" if hosts["failed"] or hosts["unreachable"] else "successful",
        "hosts": hosts, "tasks": tasks,
    }

def rpc(url, token, method, params, timeout=5, verify_tls=True):
    body = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode()
    headers = {"Content-Type": "application/json-rpc", "Authorization": "Bearer " + token}
    req = urllib.request.Request(url, data=body, headers=headers)
    ctx = None if verify_tls else ssl._create_unverified_context()
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as response:
        result = json.load(response)
    if "error" in result:
        raise RuntimeError("Zabbix API error: " + str(result["error"]))
    if "result" not in result:
        raise RuntimeError("Missing JSON-RPC result")
    return result["result"]

def push(config, token, item_key, record):
    z = config["zabbix"]
    result = rpc(z["url"], token, "history.push", [{
        "host": z["host"], "key": item_key,
        "value": json.dumps(record, separators=(",", ":"))
    }], timeout=int(z.get("timeout_seconds", 5)),
       verify_tls=bool(z.get("verify_tls", True)))
    # Zabbix history.push responses vary by server version; inspect actual response.
    if not isinstance(result, list) or len(result) != 1:
        raise RuntimeError("Unexpected history.push response: " + repr(result))
    entry = result[0]
    if not isinstance(entry, dict) or entry.get("response") != "success":
        raise RuntimeError("history.push rejected: " + repr(entry))
    return result
