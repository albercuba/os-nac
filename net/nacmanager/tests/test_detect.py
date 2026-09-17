import importlib.util
import xml.etree.ElementTree as ET
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'src' / 'opnsense' / 'scripts' / 'Nacmanager' / 'detect.py'
spec = importlib.util.spec_from_file_location('detect', SCRIPT)
detect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(detect)


def test_normalize_mac_formats():
    assert detect.normalize_mac('bc:0f:f3:92:b3:3a') == 'BC0FF392B33A'
    assert detect.normalize_mac('BC0FF392B33A') == 'BC0FF392B33A'
    assert detect.normalize_mac('john.doe') is None


def test_reject_line_extracts_mab_identity_and_metadata():
    line = 'Mon Sep 15 10:00:00 2026 : Login incorrect: [BC0FF392B33A/BC0FF392B33A] (from client usw-pro-24 port 12 cli bc-0f-f3-92-b3-3a)'
    event = detect.event_from_line(line)
    assert event['radius_identity'] == 'BC0FF392B33A'
    assert event['mac'] == 'BC:0F:F3:92:B3:3A'
    assert event['auth_result'] == 'reject'
    assert event['auth_method'] == 'mac'
    assert event['calling_station_id'] == 'bc-0f-f3-92-b3-3a'
    assert event['switch_name'] == 'usw-pro-24'
    assert event['switch_port'] == '12'


def test_accept_line_extracts_result():
    line = 'radiusd: Access-Accept for user 84253F58D4F1 from client 192.168.10.20 port 50001'
    event = detect.event_from_line(line)
    assert event['radius_identity'] == '84253F58D4F1'
    assert event['auth_result'] == 'accept'
    assert event['nas_ip'] == '192.168.10.20'


def test_non_mac_user_ignored():
    assert detect.event_from_line('Login incorrect: [john.doe/password]') is None


def test_access_reject_with_calling_station_id_only():
    line = 'radiusd: Access-Reject for user host/ignored Calling-Station-Id := "00-11-32-22-07-73" NAS-IP-Address = 192.168.10.20 NAS-Port-Id = Gi1/0/12'
    event = detect.event_from_line(line)
    assert event['radius_identity'] == '001132220773'
    assert event['mac'] == '00:11:32:22:07:73'
    assert event['auth_result'] == 'reject'
    assert event['auth_method'] == 'eap'
    assert event['nas_ip'] == '192.168.10.20'
    assert event['nas_port'] == 'Gi1/0/12'
    assert event['switch_ip'] == '192.168.10.20'
    assert event['switch_name'] == '192.168.10.20'
    assert event['switch_port'] == 'Gi1/0/12'


def test_peap_host_identity_extracts_metadata_but_is_not_mac_auth():
    line = 'Auth: (22) Login incorrect (eap_peap: (TLS) PEAP - Alert read:fatal:certificate expired): [host/Alberto-XPS13/<via Auth-Type = eap>] (from client rgts-prd-sw-01 port 14 cli cc:48:3a:b1:46:f8)'
    event = detect.event_from_line(line)
    assert event['radius_identity'] == 'CC483AB146F8'
    assert event['auth_method'] == 'eap'
    assert event['hostname'] == 'Alberto-XPS13'
    assert event['switch_name'] == 'rgts-prd-sw-01'
    assert event['switch_port'] == '14'


def test_log_paths_expands_globs_and_preserves_order(tmp_path):
    radius_dir = tmp_path / 'radius'
    radius_dir.mkdir()
    latest = radius_dir / 'latest.log'
    extra = radius_dir / 'radius.log'
    latest.write_text('')
    extra.write_text('')
    missing = tmp_path / 'missing.log'
    paths = detect.log_paths([str(latest), str(radius_dir / '*.log'), str(missing)])
    assert paths[0] == str(latest)
    assert str(extra) in paths
    assert str(missing) in paths
    assert paths.count(str(latest)) == 1


def test_read_new_lines_tracks_cursor(tmp_path, monkeypatch):
    state_file = tmp_path / 'detect_state.json'
    log_file = tmp_path / 'radius.log'
    monkeypatch.setattr(detect, 'STATE', str(state_file))
    log_file.write_text('first\nsecond\n')
    state = detect.load_state()
    assert detect.read_new_lines(str(log_file), state) == ['first', 'second']
    detect.save_state(state)
    log_file.write_text('first\nsecond\nthird\n')
    state = detect.load_state()
    assert detect.read_new_lines(str(log_file), state) == ['third']


def test_upsert_event_updates_existing_without_duplicate():
    root = ET.Element('root')
    event = {
        'radius_identity': 'BC0FF392B33A',
        'mac': 'BC:0F:F3:92:B3:3A',
        'calling_station_id': 'bc-0f-f3-92-b3-3a',
        'hostname': 'printer-01',
        'nas_ip': '192.168.10.20',
        'nas_port': '1',
        'switch_name': 'usw-pro-24',
        'switch_ip': '192.168.10.20',
        'switch_port': '1',
        'auth_result': 'reject',
    }
    assert detect.upsert_event(root, event) is True
    event['nas_port'] = '2'
    event['switch_port'] = '2'
    assert detect.upsert_event(root, event) is False
    devices = root.findall('./OPNsense/nacmanager/devices/device')
    assert len(devices) == 1
    assert devices[0].findtext('hostname') == 'printer-01'
    assert devices[0].findtext('nas_port') == '2'
    assert devices[0].findtext('switch_name') == 'usw-pro-24'
    assert devices[0].findtext('switch_ip') == '192.168.10.20'
    assert devices[0].findtext('switch_port') == '2'
    assert devices[0].findtext('port_last_seen')
