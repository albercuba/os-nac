#!/usr/local/bin/python3

import json
import os
import subprocess
import xml.etree.ElementTree as ET

CONFIG = '/conf/config.xml'
AUTHORIZE = '/usr/local/etc/raddb/mods-config/files/authorize'


def main():
    data = {
        'config_exists': os.path.exists(CONFIG),
        'authorize_exists': os.path.exists(AUTHORIZE),
        'radius_status': '',
        'counts': {'unknown': 0, 'allowed': 0, 'blocked': 0},
    }
    try:
        proc = subprocess.run(['/usr/local/etc/rc.d/radiusd', 'status'], capture_output=True, text=True, timeout=10)
        data['radius_status'] = (proc.stdout + proc.stderr).strip()
    except Exception as err:
        data['radius_status'] = str(err)
    if os.path.exists(CONFIG):
        root = ET.parse(CONFIG).getroot()
        for device in root.findall('./OPNsense/nacmanager/devices/device'):
            status = device.findtext('status') or 'unknown'
            if status in data['counts']:
                data['counts'][status] += 1
    print(json.dumps(data, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
