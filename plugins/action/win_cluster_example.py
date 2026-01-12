
"""Example controller-side Action plugin
Purpose: Demonstrate an Action plugin executed on the Ansible controller.
This simple plugin sets `result['msg']` which is printed by the playbook.
"""
from ansible.plugins.action import ActionBase

class ActionModule(ActionBase):
    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)
        # Populate a friendly message for the playbook to display
        result['msg'] = 'Action plugin executed on controller'
        return result
