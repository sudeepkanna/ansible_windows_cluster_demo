import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ansible_collections/enterprise/automation_kpi/plugins/module_utils'))
from kpi_core import classify, item_key, summarize, create_payload
CONFIG = {'reporting': {'enabled': True, 'jobs': {'Desired State': 'desired_state'},
          'inventories': {'Prod': 'prod'}, 'allowed_domains': ['domain_a']},
          'zabbix': {'key_prefix': 'aap.job.raw'}}
META = {'awx_job_id': 55, 'awx_job_template_name': 'Desired State',
        'awx_inventory_name': 'Prod', 'domain_id': 'domain_a'}
class Stats:
    processed = {'host1': True, 'host2': True, 'host3': True}
    def summarize(self, host):
        return {'host1': {'ok': 4, 'changed': 2}, 'host2': {'failures': 1},
                'host3': {'unreachable': 1}}[host]
class CoreTests(unittest.TestCase):
    def test_mapping(self):
        self.assertEqual(item_key(CONFIG, classify(CONFIG, META)),
                         'aap.job.raw[desired_state,prod,domain_a]')
    def test_default_deny(self):
        self.assertIsNone(classify(CONFIG, {**META, 'domain_id': 'not_approved'}))
    def test_recap(self):
        hosts, tasks = summarize(Stats())
        self.assertEqual(hosts, {'passed': 1, 'failed': 1, 'unreachable': 1})
        self.assertEqual(tasks['changed'], 2)
    def test_payload(self):
        p = create_payload(META, classify(CONFIG, META), Stats(), 5.4)
        self.assertEqual(p['job_id'], 55)
        self.assertEqual(p['recap_status'], 'failed')
