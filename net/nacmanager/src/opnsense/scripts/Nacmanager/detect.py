#!/usr/local/bin/python3

import datetime
import glob
import json
import os
import re
import sys
import tempfile
import uuid
import xml.etree.ElementTree as ET

CONFIG = os.environ.get('NACMANAGER_CONFIG', '/conf/config.xml')
STATE = os.environ.get('NACMANAGER_STATE', '/var/db/nacmanager/detect_state.json')
DEFAULT_LOG_PATTERNS = [
    '/var/log/radius/latest.log',
    '/var/log/radius/radius.log',
    '/var/log/radius/*.log',
    '/var/log/radius.log',
    '/var/log/system/latest.log',
]
LOG_PATTERNS = os.environ.get(
    'NACMANAGER_LOGS',
    ':'.join(DEFAULT_LOG_PATTERNS),
).split(':')
TAIL_LIMIT = int(os.environ.get('NACMANAGER_TAIL_LIMIT', '200000'))
MAC_RE = re.compile(r'(?<![0-9A-Fa-f])([0-9A-Fa-f]{12})(?![0-9A-Fa-f])')
CALLING_RE = re.compile(r'(?:Calling-Station-Id|cli)\s*(?::=|=|:)?\s*"?([0-9A-Fa-f.:-]{12,32})"?', re.I)
NAS_RE = re.compile(r'(?:from client|NAS-IP-Address\s*(?::=|=|:)?)\s*"?([0-9]{1,3}(?:\.[0-9]{1,3}){3})"?', re.I)
CLIENT_RE = re.compile(r'from client\s+([0-9A-Za-z._:-]+)', re.I)
PORT_RE = re.compile(r'(?:port|NAS-Port(?:-Id)?\s*(?::=|=|:)?)\s*"?([0-9A-Za-z._:/-]+)"?', re.I)
USER_RE = re.compile(r'(?:\[|\buser\s+)([^/\]\s]+)', re.I)
HOST_RE = re.compile(r'(?:\[|\buser\s+)host/([^/\]<\s]+)', re.I)
EAP_RE = re.compile(r'\b(eap|peap|tls)\b|Auth-Type\s*=\s*eap', re.I)
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


def load_state():
    try:
        with open(STATE, 'r', encoding='utf-8') as handle:
            data = json.load(handle)
            return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    directory = os.path.dirname(STATE)
    if directory:
        os.makedirs(directory, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='detect_state.', suffix='.tmp', dir=directory or None)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(state, handle, sort_keys=True)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, STATE)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def log_paths(patterns=LOG_PATTERNS):
    paths = []
    seen = set()
    for pattern in patterns:
        matches = glob.glob(pattern) if any(char in pattern for char in '*?[') else [pattern]
        for path in matches:
            if path not in seen:
                paths.append(path)
                seen.add(path)
    return paths


def read_new_lines(path, state, limit=TAIL_LIMIT):
    try:
        stat = os.stat(path)
        inode = '%s:%s' % (getattr(stat, 'st_dev', 0), getattr(stat, 'st_ino', 0))
        previous = state.get(path, {})
        offset = int(previous.get('offset', 0)) if previous.get('inode') == inode else 0
        with open(path, 'rb') as handle:
            size = stat.st_size
            if offset <= 0:
                handle.seek(max(0, size - limit), os.SEEK_SET)
            elif offset <= size:
                handle.seek(offset, os.SEEK_SET)
            else:
                handle.seek(max(0, size - limit), os.SEEK_SET)
            raw = handle.read()
            state[path] = {'inode': inode, 'offset': handle.tell()}
            return raw.decode('utf-8', 'replace').splitlines()
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
    client = CLIENT_RE.search(line)
    port = PORT_RE.search(line)
    user = USER_RE.search(line)
    host = HOST_RE.search(line)
    nas_ip = nas.group(1) if nas else ''
    switch_name = client.group(1) if client else ''
    switch_port = port.group(1) if port else ''
    auth_method = 'mac'
    if host or EAP_RE.search(line):
        user_identity = user.group(1) if user else ''
        if normalize_mac(user_identity) != identity:
            auth_method = 'eap'
    return {
        'radius_identity': identity,
        'mac': display_mac(identity),
        'auth_method': auth_method,
        'calling_station_id': calling.group(1) if calling else '',
        'hostname': host.group(1) if host else '',
        'nas_ip': nas_ip,
        'nas_port': switch_port,
        'nas_identifier': switch_name,
        'switch_name': switch_name or nas_ip,
        'switch_ip': nas_ip,
        'switch_port': switch_port,
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


def set_text(node, key, value):
    child = node.find(key)
    if child is None:
        child = ET.SubElement(node, key)
    child.text = value


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
        set_text(found, 'mac', event['mac'])
        set_text(found, 'radius_identity', identity)
        set_text(found, 'first_seen', timestamp)
        created = True
    current_status = found.findtext('status') or ''
    status = 'allowed' if radius_allowed(root, identity) else 'unknown'
    if current_status == 'blocked':
        status = 'blocked'
    updates = {
        'last_seen': timestamp,
        'nas_ip': event.get('nas_ip', ''),
        'nas_port': event.get('nas_port', ''),
        'hostname': event.get('hostname', ''),
        'switch_name': event.get('switch_name', ''),
        'switch_ip': event.get('switch_ip', ''),
        'switch_port': event.get('switch_port', ''),
        'port_last_seen': timestamp if event.get('switch_name') or event.get('switch_ip') or event.get('switch_port') else '',
        'calling_station_id': event.get('calling_station_id', ''),
        'auth_result': event.get('auth_result', 'unknown'),
        'status': status,
    }
    for key, value in updates.items():
        if value != '' or found.find(key) is None:
            set_text(found, key, value)
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
        print('missing %s' % CONFIG)
        return 1
    state = load_state()
    tree = ET.parse(CONFIG)
    root = tree.getroot()
    events = []
    for path in log_paths():
        for line in read_new_lines(path, state):
            event = event_from_line(line)
            if event is not None:
                events.append(event)
    created = 0
    changed = 0
    ignored = 0
    for event in events:
        if event.get('auth_method', 'mac') != 'mac':
            ignored += 1
            continue
        if upsert_event(root, event):
            created += 1
        changed += 1
    if changed:
        atomic_write(tree)
    save_state(state)
    print('processed=%d discovered=%d ignored=%d' % (len(events), created, ignored))
    return 0


if __name__ == '__main__':
    sys.exit(main())
