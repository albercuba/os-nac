# os-nac / NAC Manager

`os-nac` is an OPNsense MVC plugin scaffold for MAC-based NAC management alongside the existing `os-freeradius` plugin. It targets OPNsense 25.7 and FreeRADIUS MAB/802.1X workflows where the switch sends a 12-hex-digit MAC address as both RADIUS username and password.

> Status: MVP scaffold. The plugin source, model, APIs, views, scripts, and parser tests are present, but it still needs live OPNsense 25.7 lab validation before production use. See [`roadmap.md`](roadmap.md) for the hardening plan.

Example:

- MAC: `bc:0f:f3:92:b3:3a`
- RADIUS username/password: `BC0FF392B33A`

## Current capabilities

- Discover MAC-format FreeRADIUS authentication attempts from recent logs with cursor-based incremental scanning.
- Track unknown and blocked endpoint devices in NAC Manager state.
- Read allowed endpoint devices from existing FreeRADIUS users with 12-hex usernames.
- Approve unknown devices by creating/updating FreeRADIUS MAC users.
- Edit VLAN, description, and enabled state for MAC-auth FreeRADIUS users.
- Revoke or block MAC-auth users without touching non-MAC FreeRADIUS accounts.
- Show diagnostics for FreeRADIUS status, VLAN/fallback settings, duplicate MAC-user warnings, blocked sync output, and device counts.

## Upstream FreeRADIUS audit

The current upstream OPNsense plugin inspected from `github.com/opnsense/plugins/net/freeradius` uses these integration points:

- User model: `src/opnsense/mvc/app/models/OPNsense/Freeradius/User.xml`
  - Mount: `//OPNsense/freeradius/user`
  - Repeating item: `users.user`
  - Relevant fields: `enabled`, `username`, `password`, `passwordencryption`, `description`, `vlan`
- VLAN rendering: `src/opnsense/service/templates/OPNsense/Freeradius/users`
  - VLAN attributes render only when `OPNsense.freeradius.general.vlanassign == 1`
  - Rendered attributes are `Tunnel-Type = VLAN`, `Tunnel-Medium-Type = IEEE-802`, and `Tunnel-Private-Group-Id = <vlan>`
- Runtime target: `users:/usr/local/etc/raddb/mods-config/files/authorize` in `+TARGETS`
- Reconfigure path: `src/opnsense/mvc/app/controllers/OPNsense/Freeradius/Api/ServiceController.php`
  - Stops FreeRADIUS
  - Runs `template reload OPNsense/Freeradius`
  - Starts FreeRADIUS when enabled
- Configd actions: `freeradius start`, `freeradius stop`, `freeradius restart`, `freeradius status`
- FreeRADIUS logs are exposed to OPNsense diagnostics through `src/opnsense/scripts/syslog/logformats/freeradius.py` and the `radiusd` syslog facility.

## Integration plan

NAC Manager reuses the existing FreeRADIUS user model instead of replacing FreeRADIUS.

1. Detect MAC-format FreeRADIUS auth attempts from logs.
2. Store discovery/blocked metadata in `//OPNsense/nacmanager`.
3. Read allowed MAC users from `OPNsense\Freeradius\User`.
4. Approve a device by creating/updating a 12-hex FreeRADIUS user:
   - `username = MAC_WITHOUT_SEPARATORS`
   - `password = MAC_WITHOUT_SEPARATORS`
   - `passwordencryption = Cleartext-Password`
   - `vlan = admin-selected VLAN`
5. Reconfigure FreeRADIUS using the existing template/reload service path.
6. Block a device by removing any matching FreeRADIUS MAC user and persisting NAC blocked state.
7. Render a managed reject stanza for blocked MACs after FreeRADIUS template reload so blocked devices remain explicit rejects.

## Dependency map

- Runtime dependency: `os-freeradius` / `freeradius3`
- Authoritative source for allowed endpoint devices: `OPNsense.freeradius.user.users.user`
- Authoritative source for unknown/blocked state: `OPNsense.nacmanager.devices.device`
- Generated runtime output: `/usr/local/etc/raddb/mods-config/files/authorize`
- Service control: `configd` actions for `freeradius` and `nacmanager`

## File tree

```text
net/nacmanager/
├── Makefile
├── pkg-descr
└── src/opnsense/
    ├── mvc/app/controllers/OPNsense/Nacmanager/
    │   ├── AllowedController.php
    │   ├── DevicesController.php
    │   ├── DiagnosticsController.php
    │   └── Api/
    │       ├── AllowedController.php
    │       ├── DevicesController.php
    │       └── DiagnosticsController.php
    ├── mvc/app/models/OPNsense/Nacmanager/
    │   ├── Nacmanager.php
    │   ├── Nacmanager.xml
    │   ├── ACL/ACL.xml
    │   └── Menu/Menu.xml
    ├── mvc/app/views/OPNsense/Nacmanager/
    │   ├── allowed.volt
    │   ├── blocked.volt
    │   ├── diagnostics.volt
    │   └── unknown.volt
    ├── service/conf/actions.d/actions_nacmanager.conf
    └── scripts/Nacmanager/
        ├── detect.py
        ├── diagnostics.py
        └── sync_blocked.py
```

## Data model

Persistent NAC Manager records contain:

- `mac`
- `radius_identity`
- `first_seen`
- `last_seen`
- `nas_ip`
- `nas_port`
- `calling_station_id`
- `auth_result`
- `status`: `unknown`, `allowed`, `blocked`
- `assigned_vlan`
- `description`
- `notes`
- `managed_by`
- `updated_at`

Allowed devices are not duplicated as the primary source. They are synchronized from FreeRADIUS users whose username matches `^[0-9A-Fa-f]{12}$`.

## Block/deny strategy

Blocked devices are represented in NAC Manager state and are removed from the FreeRADIUS allow-list. To guarantee rejection even when FreeRADIUS fallback VLAN is enabled, `sync_blocked.py` renders explicit `Auth-Type := Reject` entries into the generated FreeRADIUS `authorize` file after template reload.

This is a runtime synchronization step, not the persistent source of truth. Persistent blocked state lives in the OPNsense NAC Manager model. A future upstream-quality improvement would add an official include hook or deny-list model to `os-freeradius` so this runtime patching step is unnecessary.

## API

Implemented endpoints:

```text
GET    /api/nacmanager/devices/search?status=unknown|blocked|allowed
GET    /api/nacmanager/devices/get/{uuid}
POST   /api/nacmanager/devices/ingest
POST   /api/nacmanager/devices/approve/{uuid}
POST   /api/nacmanager/devices/block/{uuid}
POST   /api/nacmanager/devices/unblock/{uuid}
POST   /api/nacmanager/devices/delete/{uuid}
DELETE /api/nacmanager/devices/delete/{uuid}

GET    /api/nacmanager/allowed/search
GET    /api/nacmanager/allowed/get/{uuid}
POST   /api/nacmanager/allowed/set/{uuid}
POST   /api/nacmanager/allowed/block/{uuid}
POST   /api/nacmanager/allowed/delete/{uuid}
DELETE /api/nacmanager/allowed/delete/{uuid}

GET    /api/nacmanager/diagnostics/status
POST   /api/nacmanager/diagnostics/detect
```

## UI

Pages added under `Services → NAC Manager`:

- `Unknown Devices`
- `Allowed Devices`
- `Blocked Devices`
- `Diagnostics`

The Allowed page intentionally shows only 12-hex MAC identities. Normal FreeRADIUS accounts such as `john.doe`, `administrator`, or `vpnuser` are not classified as NAC endpoint devices.

## Installation for development

Use these copy-based steps only for a lab firewall. The preferred production path is an OPNsense plugin package after package-build validation.

From this repository root:

```sh
scp -r net/nacmanager/src/opnsense/* root@<firewall-ip>:/usr/local/opnsense/
scp net/nacmanager/src/opnsense/service/conf/actions.d/actions_nacmanager.conf root@<firewall-ip>:/usr/local/opnsense/service/conf/actions.d/
ssh root@<firewall-ip> 'chmod +x /usr/local/opnsense/scripts/Nacmanager/*.py && service configd restart'
```

For package builds, copy `net/nacmanager` into an OPNsense plugins build tree and run:

```sh
cd /usr/plugins/net/nacmanager
make package
pkg install /usr/obj/usr/plugins/net/nacmanager/*.pkg
service configd restart
```

## Configuration

1. Install and configure `os-freeradius`.
2. Enable FreeRADIUS.
3. Enable VLAN assignment in FreeRADIUS if VLAN responses are desired.
4. Configure UniFi to send MAB usernames/passwords as 12-hex MAC identities.
5. Run detection from `Services → NAC Manager → Diagnostics` or via:

```sh
configctl nacmanager detect
```

For periodic detection, add an OPNsense cron job that runs this configd action:

```sh
configctl nacmanager detect_scheduled
```

The detector stores its read cursor in `/var/db/nacmanager/detect_state.json` so repeated scheduled runs process only new log data.

## Workflows

### Unknown Devices

1. Unknown endpoint sends a RADIUS Access-Request.
2. FreeRADIUS rejects it.
3. `nacmanager detect` scans recent FreeRADIUS logs and records the MAC.
4. The device appears in `Unknown Devices`.
5. Admin chooses Approve, Block, or Delete.

### Approve

Approving creates or updates a FreeRADIUS MAC user with the MAC identity as username and password, sets VLAN, saves config, reloads templates, syncs blocked rejects, and restarts FreeRADIUS if enabled.

### Allowed Devices

Allowed Devices reads live FreeRADIUS MAC users. NAC Manager can edit VLAN, description, enabled state, delete/revoke, or block. Non-MAC FreeRADIUS users are hidden.

### Blocked Devices

Blocking removes the MAC user from FreeRADIUS and records blocked state in NAC Manager. The runtime sync writes explicit FreeRADIUS reject entries so blocked MACs do not fall through to fallback VLAN acceptance.

## Testing instructions

Manual tests:

1. Unknown MAC sends RADIUS Access-Request.
   - Expected: reject in FreeRADIUS, device appears under Unknown after detection scan.
2. Approve device to VLAN 20.
   - Expected: FreeRADIUS user exists with VLAN 20; next auth Access-Accept includes VLAN 20.
3. Change VLAN to 40.
   - Expected: same FreeRADIUS user updated; no duplicate; next auth returns VLAN 40.
4. Block allowed device.
   - Expected: FreeRADIUS user removed; explicit reject block rendered; future auth rejects.
5. Unblock and approve.
   - Expected: device can be approved again and returns to Allowed.
6. Existing external FreeRADIUS MAC user.
   - Expected: appears in Allowed and can be edited.
7. Existing non-MAC FreeRADIUS user.
   - Expected: not shown in Allowed.
8. Reboot.
   - Expected: NAC Manager state persists in `/conf/config.xml`; FreeRADIUS users persist.
9. FreeRADIUS reconfigure.
   - Expected: run `configctl nacmanager sync` after reconfigure to restore reject stanzas.
10. Invalid MAC/VLAN API requests.
   - Expected: validation failure and no config corruption.

## Rollback / uninstall

1. Delete or disable MAC users created by NAC Manager from `Services → FreeRADIUS → Users`.
2. Remove the NAC Manager plugin package or remove copied files.
3. Remove the managed block in `/usr/local/etc/raddb/mods-config/files/authorize` if present:
   - between `# BEGIN NAC Manager blocked devices` and `# END NAC Manager blocked devices`
4. Run FreeRADIUS reconfigure.
5. Restart `configd` if files were manually copied.

## Logs and troubleshooting

- OPNsense system log receives PHP `error_log()` messages such as `nacmanager: approved <MAC>`.
- FreeRADIUS logs remain under the existing FreeRADIUS diagnostics/log facilities.
- Diagnostics page shows FreeRADIUS status, VLAN/fallback settings, sync output, and device counts.

## Known limitations

See [`roadmap.md`](roadmap.md) for planned fixes and enhancements.

- Detection is currently an idempotent incremental log scan, not a live event subscription.
- Log parsing supports several common FreeRADIUS reject/accept line formats, including quoted `Calling-Station-Id`, but may need tuning for local log verbosity.
- The explicit blocked deny-list currently patches the generated FreeRADIUS `authorize` file after template reload because upstream `os-freeradius` has no deny-list/include model for this purpose.
- The UI uses simple native tables and prompt/confirm dialogs for MVP; richer modal forms can replace these later.
- No dashboard widget is included yet.
- NAS/RADIUS clients are not modified. They remain managed by `Services → FreeRADIUS → Clients`.

## Security review

- Command injection: backend scripts do not invoke shell with user-provided values. `diagnostics.py` uses an argv list.
- Path injection: scripts use fixed OPNsense paths only.
- API authorization/CSRF: APIs are under OPNsense MVC ACL patterns and use OPNsense AJAX helpers/forms.
- Input validation: model masks and API logic validate MAC identities and VLAN IDs.
- Privilege boundaries: FreeRADIUS persistent configuration changes use OPNsense models; scripts handle log scanning and runtime deny sync only.
- Race conditions: config updates use OPNsense `Config::save()` in PHP. The detection script atomically replaces `/conf/config.xml`, but future work should use native config locking helpers.
- Concurrent edits: MVP does not include per-record optimistic locking.
- Unrelated FreeRADIUS users: only usernames matching 12 hex digits are shown/edited/deleted by Allowed Devices APIs.
- Secret exposure: RADIUS shared secrets are not read or displayed; MAC-as-password is not shown in NAC Manager tables.
- Log injection: logged values are normalized MAC identities where possible.

## Development roadmap

The next work is tracked in [`roadmap.md`](roadmap.md). The highest-priority items are live OPNsense 25.7 validation, FreeRADIUS integration hardening, detection reliability with real UniFi log samples, UI form polish, and package-build testing.
