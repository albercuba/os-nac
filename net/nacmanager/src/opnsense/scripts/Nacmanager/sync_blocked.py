#!/usr/local/bin/python3

import os
import re
import sys
import xml.etree.ElementTree as ET

CONFIG = '/conf/config.xml'
AUTHORIZE = '/usr/local/etc/raddb/mods-config/files/authorize'
START = '# BEGIN NAC Manager blocked devices\n'
END = '# END NAC Manager blocked devices\n'
MAC_RE = re.compile(r'^[0-9A-F]{12}$')


def blocked_identities():
    if not os.path.exists(CONFIG):
        return []
    root = ET.parse(CONFIG).getroot()
    identities = []
    for device in root.findall('./OPNsense/nacmanager/devices/device'):
        if (device.findtext('status') or '') != 'blocked':
            continue
        identity = re.sub(r'[^0-9A-Fa-f]', '', device.findtext('radius_identity') or device.findtext('mac') or '').upper()
        if MAC_RE.fullmatch(identity):
            identities.append(identity)
    return sorted(set(identities))


def render_block(identities):
    lines = [START]
    for identity in identities:
        lines.append('%s Auth-Type := Reject\n' % identity)
        lines.append('        Reply-Message := "NAC Manager blocked"\n\n')
    lines.append(END)
    return ''.join(lines)


def main():
    identities = blocked_identities()
    if not os.path.exists(AUTHORIZE):
        print('authorize file not found; run FreeRADIUS reconfigure first')
        return 0
    with open(AUTHORIZE, 'r', encoding='utf-8', errors='replace') as handle:
        content = handle.read()
    block = render_block(identities)
    if START in content and END in content:
        before = content.split(START, 1)[0]
        after = content.split(END, 1)[1]
        content = before + block + after
    else:
        content = block + '\n' + content
    with open(AUTHORIZE, 'w', encoding='utf-8') as handle:
        handle.write(content)
    print('blocked=%d' % len(identities))
    return 0


if __name__ == '__main__':
    sys.exit(main())
