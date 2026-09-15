import importlib.util
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'src' / 'opnsense' / 'scripts' / 'Nacmanager' / 'sync_blocked.py'
spec = importlib.util.spec_from_file_location('sync_blocked', SCRIPT)
sync_blocked = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_blocked)


def test_render_block_contains_explicit_reject():
    rendered = sync_blocked.render_block(['BC0FF392B33A'])
    assert '# BEGIN NAC Manager blocked devices' in rendered
    assert 'BC0FF392B33A Auth-Type := Reject' in rendered
    assert 'Reply-Message := "NAC Manager blocked"' in rendered
    assert '# END NAC Manager blocked devices' in rendered


def test_blocked_identities_deduplicates_and_ignores_non_blocked(tmp_path, monkeypatch):
    config = tmp_path / 'config.xml'
    config.write_text('''<?xml version="1.0"?>
<root><OPNsense><nacmanager><devices>
  <device><radius_identity>BC0FF392B33A</radius_identity><status>blocked</status></device>
  <device><mac>bc:0f:f3:92:b3:3a</mac><status>blocked</status></device>
  <device><radius_identity>001132220773</radius_identity><status>unknown</status></device>
  <device><radius_identity>not-a-mac</radius_identity><status>blocked</status></device>
</devices></nacmanager></OPNsense></root>
''')
    monkeypatch.setattr(sync_blocked, 'CONFIG', str(config))
    assert sync_blocked.blocked_identities() == ['BC0FF392B33A']
