"""AAP aggregate KPI callback. Verify variable resolution in actual EE before production."""
import os
import time
from ansible.plugins.callback import CallbackBase
from ansible_collections.enterprise.automation_kpi.plugins.module_utils.kpi_core import (
    classify, item_key, create_payload, extract_selected, encode)
from ansible_collections.enterprise.automation_kpi.plugins.module_utils.zabbix_api import push

DOCUMENTATION = r"""
name: kpi
type: aggregate
short_description: Publish approved AAP job-level KPI data to Zabbix
description:
  - Collects final native Ansible recap and optional allowlisted numeric task results.
  - Metadata option resolution is version-dependent and must be validated inside the EE.
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
"""

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'enterprise.automation_kpi.kpi'
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self):
        super().__init__()
        self.started = time.monotonic()
        self.resolved = False
        self.finished = False
        self.config = None
        self.meta = {}
        self.context = None
        self.selected = {}
        self.debug = False

    def log(self, message):
        if self.debug:
            self._display.display('AAP_KPI: ' + message)

    def resolve_metadata(self, play):
        names = ('awx_job_id', 'awx_job_template_name', 'awx_inventory_name', 'domain_id')
        values, sources = {}, []
        for name in names:
            try:
                v = self.get_option(name)
                if v is not None and str(v) != '':
                    values[name] = v
                    sources.append('option:' + name)
            except (AttributeError, KeyError, ValueError):
                pass
        # Internal ansible-core compatibility fallback: confirm against EE version.
        manager = None
        getter = getattr(play, 'get_variable_manager', None)
        if callable(getter):
            try:
                manager = getter()
                sources.append('play.get_variable_manager')
            except Exception:
                pass
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
                self.log('variable-manager probe: ' + type(exc).__name__)
        return values, ','.join(sources) or 'UNRESOLVED'

    def v2_playbook_on_play_start(self, play):
        if self.resolved:
            return
        self.resolved = True
        try:
            import yaml
            path = os.environ.get('AAP_KPI_CONFIG', 'config/reporting.yml')
            with open(path, encoding='utf8') as f:
                self.config = yaml.safe_load(f)
            self.debug = bool(self.config['reporting'].get('debug', False))
            self.meta, source = self.resolve_metadata(play)
            self.context = classify(self.config, self.meta)
            self.log('metadata source: ' + source)
            self.log('job_id={!r} job={!r} inventory={!r} domain={!r} approved={}'.format(
                self.meta.get('awx_job_id'), self.meta.get('awx_job_template_name'),
                self.meta.get('awx_inventory_name'), self.meta.get('domain_id'), bool(self.context)))
        except Exception as exc:
            self.context = None
            self.log('nonfatal context error: ' + type(exc).__name__)

    def _capture(self, result):
        if not self.context:
            return
        try:
            rules = self.config['reporting'].get('selected_tasks', {})
            extract_selected(result, rules, self.selected)
        except Exception as exc:
            self.log('selected task capture error: ' + type(exc).__name__)

    def v2_runner_on_ok(self, result):
        self._capture(result)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._capture(result)

    def v2_runner_on_unreachable(self, result):
        self._capture(result)

    def v2_playbook_on_stats(self, stats):
        if self.finished:
            return
        self.finished = True
        if not self.context:
            self.log('skip: context not approved or unresolved')
            return
        token = os.environ.get('ZABBIX_API_TOKEN')
        if not token:
            self.log('skip: no ZABBIX_API_TOKEN')
            return
        try:
            record = create_payload(self.meta, self.context, stats,
                                    time.monotonic() - self.started, self.selected)
            key = item_key(self.config, self.context)
            push(self.config['zabbix'], token, key, encode(record))
            self.log('published job_id={} key={}'.format(record['job_id'], key))
        except Exception as exc:
            self.log('nonfatal publish failure: ' + type(exc).__name__)
