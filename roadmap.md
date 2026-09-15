# os-nac roadmap

This roadmap tracks the work needed to move NAC Manager from the current MVP scaffold to a production-ready OPNsense plugin.

## Current state

The repository contains a first implementation of an OPNsense MVC plugin under `net/nacmanager`.

Implemented:

- [X] Native OPNsense plugin layout with `Makefile` and `pkg-descr`
- [X] MVC model, menu, ACL, controllers, API controllers, and Volt views
- [X] Unknown, Allowed, Blocked, and Diagnostics pages
- [X] Persistent NAC Manager device state model for discovered and blocked devices
- [X] FreeRADIUS MAC-user integration through the existing `OPNsense\Freeradius\User` model
- [X] Approval flow that creates or updates 12-hex MAC users in FreeRADIUS
- [X] Allowed-device view synchronized from existing FreeRADIUS MAC-format users
- [X] Block flow that revokes matching FreeRADIUS MAC users
- [X] Runtime blocked-device reject synchronization for FreeRADIUS fallback-VLAN safety
- [X] Log-scanning detection script and parser unit tests

Not yet verified:

- [ ] Live install on OPNsense 25.7
- [ ] PHP syntax/runtime behavior on OPNsense
- [ ] End-to-end UniFi MAB authentication flows
- [ ] Package build inside an OPNsense plugins tree

## Milestone 1: Lab validation

Goal: prove the current scaffold loads and works on an OPNsense 25.7 lab firewall.

- [ ] Install by development copy to `/usr/local/opnsense`.
- [ ] Run `php -l` on all PHP files on the firewall.
- [ ] Restart `configd` and verify `configctl nacmanager status`, `detect`, `sync`, and `diagnostics` actions exist.
- [ ] Confirm menu entries appear under `Services → NAC Manager`.
- [ ] Confirm API ACL access works for an administrator account.
- [ ] Verify Unknown, Allowed, Blocked, and Diagnostics pages render without browser console errors.
- [ ] Verify FreeRADIUS remains manageable from `Services → FreeRADIUS`.

Exit criteria:

- [ ] No PHP syntax errors.
- [ ] No `configd` action errors.
- [ ] All pages load in the OPNsense UI.

## Milestone 2: FreeRADIUS integration hardening

Goal: make FreeRADIUS updates safer, more native, and repeatable.

- [ ] Confirm exact OPNsense 25.7 model method behavior for adding/deleting `OPNsense\Freeradius\User` nodes.
- [ ] Add duplicate-MAC checks with clear validation errors.
- [ ] Confirm VLAN assignment behavior when `freeradius.general.vlanassign` is disabled and show a warning in Diagnostics.
- [ ] Decide whether approvals should automatically enable `vlanassign` or require the admin to enable it in FreeRADIUS.
- [ ] Add a safer native hook for blocked-device reject rules if possible.
- [ ] Investigate whether an upstream-compatible FreeRADIUS template include point can replace post-generation `authorize` patching.
- [ ] Ensure blocked reject entries are restored after every FreeRADIUS reconfigure and firewall reboot.

Exit criteria:

- [ ] Approve, edit VLAN, revoke, block, unblock, and approve-again flows work without duplicate users.
- [ ] Blocked devices reject even when FreeRADIUS fallback VLAN is enabled.

## Milestone 3: Detection reliability

Goal: make unknown-device discovery reliable for real UniFi/FreeRADIUS logs.

- [ ] Capture actual OPNsense 25.7 FreeRADIUS log lines for UniFi MAB rejects and accepts.
- [ ] Extend parser tests with real sanitized log samples.
- [ ] Track a read cursor/state file to avoid repeatedly scanning the same events.
- [ ] Add idempotent update behavior for repeated attempts from the same MAC.
- [ ] Preserve latest NAS IP, NAS port, Calling-Station-Id, and auth result.
- [ ] Evaluate accounting/detail logs or a dedicated FreeRADIUS policy/log rule as a cleaner event source.
- [ ] Add a cron/configd scheduling option for periodic detection.

Exit criteria:

- [ ] Unknown UniFi MAB clients appear automatically and consistently.
- [ ] Repeated attempts update `last_seen` without creating duplicates.

## Milestone 4: UI polish

Goal: replace MVP prompt/confirm interactions with maintainable native OPNsense dialogs.

- [ ] Replace JavaScript `prompt()` calls with OPNsense dialog XML/forms.
- [ ] Add searchable/sortable native grids using `UIBootgrid` where practical.
- [ ] Add status badges with consistent colors.
- [ ] Add last-seen age formatting.
- [ ] Show Unknown count prominently.
- [ ] Add confirmation dialogs for destructive actions.
- [ ] Add clearer validation feedback for invalid VLANs/MACs.
- [ ] Add optional notes editing.

Exit criteria:

- [ ] UI feels consistent with native OPNsense pages.
- [ ] All destructive actions require explicit confirmation.

## Milestone 5: Testing and security review

Goal: add repeatable tests and document security behavior.

- [ ] Add parser tests for more log formats.
- [ ] Add mocked XML config tests for approve/block/sync scripts where practical.
- [ ] Add documented `radtest` or `radclient` procedures for Access-Reject/Access-Accept testing.
- [ ] Test malformed MAC and invalid VLAN API requests.
- [ ] Review command injection, path injection, CSRF, ACL, and log injection boundaries.
- [ ] Review concurrent edits and config write locking.
- [ ] Confirm RADIUS shared secrets and plaintext passwords are never displayed or logged.

Exit criteria:

- [ ] Documented test matrix passes on lab firewall.
- [ ] Security review issues are either fixed or tracked.

## Milestone 6: Packaging and release

Goal: produce installable artifacts and release notes.

- [ ] Build in an OPNsense plugins tree.
- [ ] Confirm package name and category conventions.
- [ ] Add versioning and changelog.
- [ ] Test package install, upgrade, reinstall, and removal.
- [ ] Document rollback from package install.
- [ ] Tag a first lab release.

Exit criteria:

- [ ] Package installs cleanly on OPNsense 25.7.
- [ ] Upgrade/reinstall does not lose NAC Manager state or FreeRADIUS users.

## Milestone 7: Switch-level visibility and automatic enforcement

Goal: move beyond "MAC authenticated or not" toward real NAC behavior — knowing *where* a device is physically connected, reacting automatically to unknown/rogue devices, and catching MAC spoofing. This is the set of capabilities that separates NAC Manager from a plain MAB allow-list, inspired by commercial NAC tools like Macmon.

This milestone can be split into three independently shippable phases.

### Phase 7a: SNMP switch inventory and port mapping

Goal: know which switch port a MAC is physically connected to, not just that it authenticated.

Data model changes (`OPNsense\Nacmanager`):

- New repeating node `switches.switch`:
  - `host` (IP/hostname)
  - `description`
  - `snmp_version` (`v2c` | `v3`)
  - `community` (v2c) or `v3` auth/priv credentials
  - `enabled`
  - `poll_interval`
- Extend `devices.device` with:
  - `switch_uuid` (reference to `switches.switch`)
  - `switch_port` (ifIndex/ifName)
  - `port_last_seen`

New script: `snmp_poll.py`

- Walks `dot1dTpFdbTable` / `Q-BRIDGE-MIB` (and optionally `LLDP-MIB`/`CDP` where supported) on each configured switch.
- Resolves MAC → `ifIndex` → port name via `IF-MIB::ifName`.
- Writes `switch_uuid` / `switch_port` / `port_last_seen` onto matching NAC Manager device records.
- Runs on the same `configd` scheduling mechanism as `detect.py`.

API additions:

```
GET    /api/nacmanager/switches/search
GET    /api/nacmanager/switches/get/{uuid}
POST   /api/nacmanager/switches/add
POST   /api/nacmanager/switches/set/{uuid}
POST   /api/nacmanager/switches/del/{uuid}
POST   /api/nacmanager/switches/test/{uuid}   # SNMP connectivity check
```

UI additions:

- New `Switches` page under `Services → NAC Manager` to manage SNMP targets (mirrors the existing FreeRADIUS Clients pattern).
- `Port` column added to Unknown/Allowed/Blocked device grids.

Exit criteria:

- [ ] Configured switches are polled on schedule without errors.
- [ ] Device records show a current switch/port for devices seen within the poll interval.
- [ ] SNMP failures surface in Diagnostics without breaking detection/approve/block flows.

### Phase 7b: MAC-spoofing detection and OUI/vendor identification

Goal: flag suspicious duplicate MAC activity and make the device list human-readable.

Data model changes:

- Extend `devices.device` with:
  - `vendor` (OUI lookup result)
  - `device_type_guess` (heuristic label, e.g. "IP phone", "printer")
  - `spoof_suspected` (bool)
  - `spoof_detected_at`
  - `spoof_detail` (free text: conflicting ports/NAS seen)

New script: `spoof_detect.py`

- Compares recent `port_last_seen`/`nas_port` history per MAC.
- Flags a device when the same MAC appears on two different switch ports (or two different NAS devices) within a short, configurable time window.
- Local OUI table (vendored, periodically refreshable) used to populate `vendor` and seed `device_type_guess`.

API additions:

```
GET    /api/nacmanager/diagnostics/spoofAlerts
POST   /api/nacmanager/devices/clearSpoofFlag/{uuid}
```

UI additions:

- Vendor/device-type columns in device grids.
- Spoof-alert banner/badge in Diagnostics and on affected device rows.

Exit criteria:

- [ ] A MAC seen on two ports within the detection window is flagged and visible in Diagnostics.
- [ ] Vendor is populated for known OUIs without manual lookup.

### Phase 7c: Quarantine VLAN and automatic port enforcement

Goal: react automatically to unknown or blocked devices instead of relying solely on FreeRADIUS reject/fallback-VLAN behavior.

Data model changes:

- Add `quarantine_vlan` to plugin-wide settings (`general` section).
- Extend `devices.status` enum: `unknown`, `quarantined`, `allowed`, `blocked` (new `quarantined` state).
- Extend `devices.device` with:
  - `expires_at` (optional, for time-boxed approvals)
  - `enforcement_mode` (`radius_only` | `radius_plus_port`)

New/extended scripts:

- `detect.py`: when `quarantine_vlan` is configured, newly discovered unknown devices are auto-approved into the quarantine VLAN (status `quarantined`) instead of sitting fully unauthenticated, giving them limited network access pending admin review.
- `enforce_port.py`: SNMP-SET against `ifAdminStatus` to administratively shut down / re-enable a switch port, used as an optional stronger enforcement action on Block (requires Phase 7a port mapping).
- `expire_access.py`: scheduled job that revokes/blocks devices past `expires_at`, for time-boxed contractor/guest-device access grants.

API additions:

```
POST   /api/nacmanager/devices/quarantine/{uuid}
POST   /api/nacmanager/devices/setExpiry/{uuid}
POST   /api/nacmanager/devices/portAction/{uuid}   # body: {"action": "shutdown"|"enable"}
```

UI additions:

- `Quarantined` tab alongside Unknown/Allowed/Blocked.
- Expiry date field on the Approve dialog (optional).
- "Shut down port" action available on Blocked devices when a mapped switch port is known.
- Quarantine VLAN field in plugin general settings.

Exit criteria:

- [ ] Unknown devices land in `quarantined` state with restricted VLAN access when the feature is enabled.
- [ ] Blocking a device with a known switch port can optionally administratively disable that port.
- [ ] Devices with an expired `expires_at` are automatically revoked without manual intervention.
- [ ] All of the above is opt-in and does not change existing behavior when disabled.

## Future enhancements

- [ ] VLAN dropdown populated from OPNsense VLAN/interface configuration
- [ ] UniFi NAS friendly names and port aliases
- [ ] Read-only NAS/RADIUS clients page
- [ ] Protected NAS/RADIUS clients editing workflow
- [ ] Bulk approve/block/delete actions
- [ ] CSV import/export
- [ ] Webhook/API notification for newly discovered unknown devices
- [ ] Dashboard widget for Unknown/Allowed/Blocked counts
- [ ] Audit history with OPNsense username attribution when available
- [ ] REST API examples for automation

> Note: "Optional quarantine VLAN workflow" and "OUI/vendor lookup" were previously listed here and have been promoted into Milestone 7 (Phases 7b/7c) above with concrete scope.

## Open design questions

1. Should NAC Manager automatically enable FreeRADIUS VLAN assignment when approving with a VLAN, or only warn when disabled?
2. Can blocked reject entries be integrated into the FreeRADIUS template through a supported include point instead of post-render patching?
3. Which FreeRADIUS event source is most reliable on OPNsense 25.7: authentication log, syslog, accounting/detail log, or generated policy logging?
4. Should deleted/revoked allowed devices return to Unknown or be removed entirely unless seen again?
5. Should disabled MAC users be shown as Allowed disabled or moved to Unknown?
6. Should SNMP credentials (Phase 7a) be stored per-switch in the plugin model, or should NAC Manager reuse OPNsense's existing SNMP/monitoring credential store if one exists?
7. Should quarantine-by-default (Phase 7c) be opt-in per-deployment or per-NAS-device, given that some networks may not want *any* unauthenticated device getting even restricted access?
