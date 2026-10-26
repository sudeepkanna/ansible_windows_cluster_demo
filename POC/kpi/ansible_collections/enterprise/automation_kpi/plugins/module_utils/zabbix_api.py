"""Small JSON-RPC client. Never log credentials or HTTP headers."""
import json
import ssl
import urllib.request

class ApiError(Exception):
    pass

def request(config, token, method, params):
    payload = json.dumps({"jsonrpc": "2.0", "method": method, "params": params, "id": 1}).encode('utf8')
    req = urllib.request.Request(config['url'], data=payload,
        headers={'Content-Type': 'application/json-rpc', 'Authorization': 'Bearer ' + token})
    context = None if config.get('verify_tls', True) else ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(req, timeout=float(config.get('timeout_seconds', 5)), context=context) as response:
            body = json.load(response)
    except Exception as exc:
        raise ApiError(f'Zabbix transport failure: {type(exc).__name__}') from exc
    if not isinstance(body, dict) or 'error' in body or 'result' not in body:
        raise ApiError('Zabbix JSON-RPC error; inspect API with separate diagnostic script')
    return body['result']

def push(config, token, key, value):
    result = request(config, token, 'history.push', [{
        'host': config['host'], 'key': key, 'value': value
    }])
    if not isinstance(result, list) or len(result) != 1:
        raise ApiError('Unexpected history.push result shape')
    if result[0].get('response') != 'success':
        raise ApiError('Zabbix history.push item rejected')
    return True
