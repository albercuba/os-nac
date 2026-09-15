import importlib.util
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
    assert event['calling_station_id'] == 'bc-0f-f3-92-b3-3a'


def test_accept_line_extracts_result():
    line = 'radiusd: Access-Accept for user 84253F58D4F1 from client 192.168.10.20 port 50001'
    event = detect.event_from_line(line)
    assert event['radius_identity'] == '84253F58D4F1'
    assert event['auth_result'] == 'accept'
    assert event['nas_ip'] == '192.168.10.20'


def test_non_mac_user_ignored():
    assert detect.event_from_line('Login incorrect: [john.doe/password]') is None
