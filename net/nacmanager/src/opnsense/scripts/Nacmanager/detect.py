#!/usr/local/bin/python3

import datetime
import os
import re
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET

CONFIG = '/conf/config.xml'
LOGS = [
    '/var/log/radius/radius.log',
    '/var/log/radius.log',
    '/var/log/system/latest.log',
]
MAC_RE = re.compile(r'(?<![0-9A-Fa-f])([0-9A-Fa-f]{12})(?![0-9A-Fa-f])')
CALLING_RE = re.compile(r'(?:Calling-Station-Id|cli)\s*[=:]?\s*([0-9A-Fa-f.:-]{12,32})', re.I)
NAS_RE = re.compile(r'(?:from client|NAS-IP-Address\s*=)\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})', re.I)
PORT_RE = re.compile(r'(?:port|NAS-Port(?:-Id)?\s*=)\s*([0-9A-Za-z._:/-]+)', re.I)
REJECT_RE = re.compile(r'(reject|login incorrect|invalid user|no auth-type|access-reject)', re.I)
ACCEPT_RE = re.compile(r'(access-accept|login ok)', re.I)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def normalize_mac(value):
    identity = re.sub(r'[^0-9A-Fa-f]', '', value or '').upper()
    if MAC_RE.fullmatch(identity):
        return identity
    return None


def display_mac(identity):
    return ':'.join(identity[i:i + 2] for i in range(0, 12, 2))


def ensure_path(root, names):
    node = root
    for name in names:
        child = node.find(name)
        if child is None:
            child = ET.SubElement(node, name)
        node = child
    return node


def read_tail(path, limit=200000):
    try:
        with open(path, 'rb') as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - limit), os.SEEK_SET)
            return handle.read().decode('utf-8', 'replace').splitlines()
    except FileNotFoundError:
        return []


def event_from_line(line):
    if not (REJECT_RE.search(line) or ACCEPT_RE.search(line)):
        return None
    macs = MAC_RE.findall(line)
    if not macs:
        calling = CALLING_RE.search(line)
        if calling:
            identity = normalize_mac(calling.group(1))
        else:
            return None
    else:
        identity = normalize_mac(macs[0])
    if identity is None:
        return None
    calling = CALLING_RE.search(line)
    nas = NAS_RE.search(line)
    port = PORT_RE.search(line)
    return {
        'radius_identity': identity,
        'mac': display_mac(identity),
        'calling_station_id': calling.group(1) if calling else '',
        'nas_ip': nas.group(1) if nas else '',
        'nas_port': port.group(1) if port else '',
        'auth_result': 'accept' if ACCEPT_RE.search(line) else 'reject',
    }


def radius_allowed(root, identity):
    user_parent = root.find('./OPNsense/freeradius/user/users')
    if user_parent is None:
        return False
    for user in user_parent.findall('user'):
        username = (user.findtext('username') or '').upper()
        enabled = user.findtext('enabled') or '1'
        if username == identity and enabled == '1':
            return True
    return False


def upsert_event(root, event):
    devices = ensure_path(root, ['OPNsense', 'nacmanager', 'devices'])
    identity = event['radius_identity']
    found = None
    for device in devices.findall('device'):
        if (device.findtext('radius_identity') or '').upper() == identity:
            found = device
            break
    created = False
    timestamp = now()
    if found is None:
        found = ET.SubElement(devices, 'device', {'uuid': str(uuid.uuid4())})
        ET.SubElement(found, 'mac').text = event['mac']
        ET.SubElement(found, 'radius_identity').text = identity
        ET.SubElement(found, 'first_seen').text = timestamp
        created = True
    current_status = found.findtext('status') or ''
    status = 'allowed' if radius_allowed(root, identity) else 'unknown'
    if current_status == 'blocked':
        status = 'blocked'
    for key in ['last_seen', 'nas_ip', 'nas_port', 'calling_station_id', 'auth_result', 'status']:
        child = found.find(key)
        if child is None:
            child = ET.SubElement(found, key)
        child.text = timestamp if key == 'last_seen' else event.get(key, status if key == 'status' else '')
    return created


def atomic_write(tree):
    directory = os.path.dirname(CONFIG)
    fd, tmp = tempfile.mkstemp(prefix='config.xml.', suffix='.tmp', dir=directory)
    try:
        with os.fdopen(fd, 'wb') as handle:
            tree.write(handle, encoding='utf-8', xml_declaration=True)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, CONFIG)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main():
    if not os.path.exists(CONFIG):
        print('missing /conf/config.xml')
        return 1
    tree = ET.parse(CONFIG)
    root = tree.getroot()
    events = []
    for path in LOGS:
        for line in read_tail(path):
            event = event_from_line(line)
            if event is not None:
                events.append(event)
    created = 0
    seen = set()
    for event in events:
        key = event['radius_identity']
        if key in seen:
            continue
        seen.add(key)
        if upsert_event(root, event):
            created += 1
    if events:
        atomic_write(tree)
    print('processed=%d discovered=%d' % (len(events), created))
    return 0


if __name__ == '__main__':
    sys.exit(main())
