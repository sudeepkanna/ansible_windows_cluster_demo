import os
import sys
import yaml
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'ansible_collections/enterprise/automation_kpi/plugins/module_utils'))
from zabbix_api import request
config = yaml.safe_load(Path(os.environ.get('AAP_KPI_CONFIG', 'config/reporting.yml')).read_text())
token = os.environ.get('ZABBIX_API_TOKEN')
if not token:
    sys.exit('Set ZABBIX_API_TOKEN')
print('Zabbix API version:', request(config['zabbix'], token, 'apiinfo.version', {}))
