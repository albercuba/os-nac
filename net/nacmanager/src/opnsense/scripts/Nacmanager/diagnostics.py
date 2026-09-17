#!/usr/local/bin/python3

import importlib.util
import json
import os
import subprocess
import sys
import traceback
import xml.etree.ElementTree as ET
from pathlib import Path

CONFIG = '/conf/config.xml'
AUTHORIZE = '/usr/local/etc/raddb/mods-config/files/authorize'
SCRIPT_DIR = Path(__file__).resolve().parent
DETECT_PATH = SCRIPT_DIR / 'detect.py'


def load_detect_module():
    spec = importlib.util.spec_from_file_location('nacmanager_detect', DETECT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError('could not load detect.py module spec')
    module = importlib.util.module_from_spec(spec)
    sys.modules['nacmanager_detect'] = module
    spec.loader.exec_module(module)
    return module


def log_summary(detect):
    rows = []
    for path in detect.log_paths():
        exists = os.path.exists(path)
        row = {
            'path': path,
            'exists': exists,
            'size': os.path.getsize(path) if exists else 0,
            'candidate_events_in_tail': 0,
            'error': '',
        }
        if exists:
            try:
                state = {}
                for line in detect.read_new_lines(path, state, limit=detect.TAIL_LIMIT):
                    if detect.event_from_line(line) is not None:
                        row['candidate_events_in_tail'] += 1
            except Exception as err:
                row['error'] = f'{err.__class__.__name__}: {err}'
        rows.append(row)
    return rows


def diagnostics_payload():
    detect = load_detect_module()
    data = {
        'config_exists': os.path.exists(CONFIG),
        'authorize_exists': os.path.exists(AUTHORIZE),
        'radius_status': '',
        'counts': {'unknown': 0, 'allowed': 0, 'blocked': 0},
        'logs': log_summary(detect),
        'detect_state_exists': os.path.exists(detect.STATE),
        'detect_state_path': detect.STATE,
        'diagnostics_ok': True,
        'diagnostics_error': '',
    }
    try:
        proc = subprocess.run(['/usr/local/etc/rc.d/radiusd', 'status'], capture_output=True, text=True, timeout=10)
        data['radius_status'] = (proc.stdout + proc.stderr).strip()
    except Exception as err:
        data['radius_status'] = f'{err.__class__.__name__}: {err}'
    if os.path.exists(CONFIG):
        root = ET.parse(CONFIG).getroot()
        for device in root.findall('./OPNsense/nacmanager/devices/device'):
            status = device.findtext('status') or 'unknown'
            if status in data['counts']:
                data['counts'][status] += 1
    return data


def main():
    try:
        data = diagnostics_payload()
    except Exception as err:
        data = {
            'diagnostics_ok': False,
            'diagnostics_error': f'{err.__class__.__name__}: {err}',
            'traceback': traceback.format_exc().splitlines()[-8:],
            'config_exists': os.path.exists(CONFIG),
            'authorize_exists': os.path.exists(AUTHORIZE),
            'counts': {'unknown': 0, 'allowed': 0, 'blocked': 0},
            'logs': [],
        }
    print(json.dumps(data, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
