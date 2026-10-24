import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
from kpi import classify, key_for, recap, payload

CONFIG = {'reporting': {'enabled': True,
    'jobs': {'Windows Desired State': 'desired_state'},
    'inventories': {'Windows Production': 'prod'},
    'allowed_domains': ['domain_a']}}
META = {'awx_job_id': '42', 'awx_job_template_name': 'Windows Desired State',
        'awx_inventory_name': 'Windows Production', 'domain_id': 'domain_a'}

class Stats:
    processed = {'a': True, 'b': True, 'c': True}
    def summarize(self, host):
        return {'a': {'ok': 2, 'changed': 1},
                'b': {'failures': 1}, 'c': {'unreachable': 1}}[host]

class Tests(unittest.TestCase):
    def test_classification(self):
        self.assertEqual(key_for(classify(CONFIG, META)), 'aap.job.raw[desired_state,prod,domain_a]')
    def test_default_deny(self):
        self.assertIsNone(classify(CONFIG, {**META, 'domain_id': 'unknown'}))
    def test_recap(self):
        hosts, tasks = recap(Stats())
        self.assertEqual(hosts, {'passed': 1, 'failed': 1, 'unreachable': 1})
        self.assertEqual(tasks['changed'], 1)
    def test_payload(self):
        record = payload(META, classify(CONFIG, META), Stats(), 3.4)
        self.assertEqual(record['job_id'], 42)
        self.assertEqual(record['status'], 'failed')
