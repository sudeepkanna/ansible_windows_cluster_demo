"""Idempotently provision only raw master trapper items on an EXISTING Zabbix host."""
import argparse
import os
import sys
from pathlib import Path
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ansible_collections/enterprise/automation_kpi/plugins/module_utils'))
from kpi_core import item_key
from zabbix_api import request
p = argparse.ArgumentParser()
p.add_argument('--apply', action='store_true')
a = p.parse_args()
config = yaml.safe_load(Path(os.environ.get('AAP_KPI_CONFIG', 'config/reporting.yml')).read_text())
z = config['zabbix']
keys = sorted({item_key(config, {'automation': job, 'environment': env, 'domain': domain})
               for job in config['reporting']['jobs'].values()
               for env in config['reporting']['inventories'].values()
               for domain in config['reporting']['allowed_domains']})
print('Master item keys:', *keys, sep='\n  ')
if not a.apply:
    print('DRY RUN. Pass --apply to create missing master items on existing Zabbix host.')
    sys.exit(0)
token = os.environ.get('ZABBIX_API_TOKEN')
if not token:
    sys.exit('ZABBIX_API_TOKEN is required')
hosts = request(z, token, 'host.get', {'output': ['hostid', 'host'], 'filter': {'host': [z['host']]}})
if len(hosts) != 1:
    sys.exit('Expected exactly one existing Zabbix technical host')
hostid = hosts[0]['hostid']
items = request(z, token, 'item.get', {'output': ['itemid', 'key_', 'type', 'value_type'], 'hostids': [hostid]})
by_key = {i['key_']: i for i in items}
for key in keys:
    if key in by_key:
        item = by_key[key]
        if int(item['type']) != 2 or int(item['value_type']) != 4:
            sys.exit('Incompatible existing master item: ' + key)
        print('EXISTS', key)
        continue
    result = request(z, token, 'item.create', {'hostid': hostid, 'name': 'AAP KPI raw ' + key,
                   'key_': key, 'type': 2, 'value_type': 4, 'history': '30d', 'trends': '0'})
    print('CREATED', key, result)
