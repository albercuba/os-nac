<?php

namespace OPNsense\Nacmanager\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Freeradius\General as FreeRADIUSGeneral;
use OPNsense\Freeradius\User as FreeRADIUSUser;
use OPNsense\Nacmanager\Nacmanager;

class DiagnosticsController extends ApiControllerBase
{
    public function statusAction()
    {
        $backend = new Backend();
        $statusText = $backend->configdRun('freeradius status');
        $sync = $backend->configdRun('nacmanager sync');
        $general = new FreeRADIUSGeneral();
        $nac = new Nacmanager();
        $radius = new FreeRADIUSUser();
        $counts = array('unknown' => 0, 'allowed' => 0, 'blocked' => 0, 'mac_users' => 0, 'duplicate_mac_users' => 0);
                $warnings = array();
                $macUsers = array();
        foreach ($nac->devices->device->iterateItems() as $node) {
            $status = (string)$node->status;
            if (isset($counts[$status])) {
                $counts[$status]++;
            }
        }
        foreach ($radius->users->user->iterateItems() as $node) {
            $identity = strtoupper((string)$node->username);
            if (preg_match('/^[0-9A-Fa-f]{12}$/', $identity)) {
                $counts['mac_users']++;
                if (!isset($macUsers[$identity])) {
                    $macUsers[$identity] = 0;
                }
                $macUsers[$identity]++;
            }
        }
        foreach ($macUsers as $identity => $count) {
            if ($count > 1) {
                $counts['duplicate_mac_users'] += $count;
            }
        }
        if ($counts['duplicate_mac_users'] > 0) {
            $warnings[] = 'Duplicate FreeRADIUS MAC users were found. Resolve duplicates before approving or editing affected devices.';
        }
        if ($general->vlanassign->__toString() != '1') {
            $warnings[] = 'FreeRADIUS VLAN assignment is disabled. Device VLAN values are saved but will not be returned until VLAN assignment is enabled in FreeRADIUS.';
        }
        if ($general->fallbackvlan_enabled->__toString() == '1') {
            $warnings[] = 'FreeRADIUS fallback VLAN is enabled. NAC Manager keeps blocked devices explicit-reject synced so they do not fall through to fallback acceptance.';
        }
        return array(
            'freeradius_enabled' => (string)$general->enabled,
            'vlan_assignment_enabled' => (string)$general->vlanassign,
            'fallback_vlan_enabled' => (string)$general->fallbackvlan_enabled,
            'freeradius_status' => trim($statusText),
            'blocked_sync' => trim($sync),
            'counts' => $counts,
                        'warnings' => $warnings,
        );
    }

    public function detectAction()
    {
        if ($this->request->isPost()) {
            $backend = new Backend();
            return array('response' => $backend->configdRun('nacmanager detect'));
        }
        return array('response' => 'failed');
    }
}
