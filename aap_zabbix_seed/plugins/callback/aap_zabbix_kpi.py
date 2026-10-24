import os
import sys
import time
from pathlib import Path

import yaml
from ansible.plugins.callback import CallbackBase

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))
from kpi import classify, key_for, payload, push

DOCUMENTATION = '''
name: aap_zabbix_kpi
type: aggregate
short_description: Aggregate AAP execution KPIs to Zabbix
description:
  - Experimental POC callback. Verify metadata resolution in the actual EE.
options:
  awx_job_id:
    type: str
    vars:
      - name: awx_job_id
  awx_job_template_name:
    type: str
    vars:
      - name: awx_job_template_name
  awx_inventory_name:
    type: str
    vars:
      - name: awx_inventory_name
  domain_id:
    type: str
    vars:
      - name: domain_id
'''

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'aap_zabbix_kpi'
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self.started = time.monotonic()
        self.done = False
        self.context_loaded = False
        self.config = None
        self.metadata = {}
        self.classification = None
        self.debug = True
        self.log('callback initialized')

    def log(self, message):
        if self.debug:
            self._display.display('AAP_ZABBIX_KPI: ' + message)

    def resolve(self, play):
        names = ('awx_job_id', 'awx_job_template_name', 'awx_inventory_name', 'domain_id')
        values = {}
        sources = []
        for name in names:
            try:
                value = self.get_option(name)
                if value is not None and str(value) != '':
                    values[name] = value
                    sources.append('callback_option:' + name)
            except (AttributeError, KeyError, ValueError):
                pass
        manager = None
        getter = getattr(play, 'get_variable_manager', None)
        if callable(getter):
            try:
                manager = getter()
                sources.append('play.get_variable_manager')
            except Exception as exc:
                self.log('manager method failed: ' + type(exc).__name__)
        if manager is None:
            manager = getattr(play, '_variable_manager', None)
            if manager is not None:
                sources.append('play._variable_manager')
        if manager is not None:
            try:
                variables = manager.get_vars(play=play)
                for name in names:
                    if name not in values and variables.get(name) is not None:
                        values[name] = variables[name]
            except Exception as exc:
                self.log('manager resolution failed: ' + type(exc).__name__)
        # Optional local diagnostic only; do not use as evidence of AAP variable access.
        if os.getenv('AAP_ZABBIX_ALLOW_ENV_FALLBACK') == '1':
            for name in names:
                if name not in values and os.getenv(name.upper()):
                    values[name] = os.environ[name.upper()]
                    sources.append('env:' + name)
        return values, ','.join(sources) or 'UNRESOLVED'

    def v2_playbook_on_play_start(self, play):
        if self.context_loaded:
            return
        self.context_loaded = True
        try:
            config_path = os.getenv('AAP_ZABBIX_CONFIG', 'config/reporting.yml')
            with open(config_path, encoding='utf-8') as stream:
                self.config = yaml.safe_load(stream)
            self.debug = bool(self.config['reporting'].get('debug', False))
            self.metadata, source = self.resolve(play)
            self.classification = classify(self.config, self.metadata)
            self.log('context_source=' + source)
            self.log('metadata=' + repr(self.metadata) + ' classification=' + repr(self.classification))
            if self.classification is None:
                self.log('unapproved or unresolved context; publishing disabled')
        except Exception as exc:
            self.classification = None
            self.log('context initialization error: ' + type(exc).__name__ + ': ' + str(exc))

    def v2_playbook_on_stats(self, stats):
        if self.done:
            return
        self.done = True
        if not self.classification:
            self.log('skipped: context unavailable')
            return
        token = os.getenv('ZABBIX_API_TOKEN')
        if not token:
            self.log('skipped: ZABBIX_API_TOKEN unavailable')
            return
        try:
            record = payload(self.metadata, self.classification, stats, time.monotonic() - self.started)
            key = key_for(self.classification)
            result = push(self.config, token, key, record)
            self.log('published job_id=' + str(record['job_id']) + ' key=' + key + ' result=' + repr(result))
        except Exception as exc:
            self.log('nonfatal Zabbix publication error: ' + type(exc).__name__ + ': ' + str(exc))
