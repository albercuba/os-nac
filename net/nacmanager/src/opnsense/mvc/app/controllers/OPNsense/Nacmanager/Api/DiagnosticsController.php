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
        $counts = array('unknown' => 0, 'allowed' => 0, 'blocked' => 0, 'mac_users' => 0);
        foreach ($nac->devices->device->iterateItems() as $node) {
            $status = (string)$node->status;
            if (isset($counts[$status])) {
                $counts[$status]++;
            }
        }
        foreach ($radius->users->user->iterateItems() as $node) {
            if (preg_match('/^[0-9A-Fa-f]{12}$/', (string)$node->username)) {
                $counts['mac_users']++;
            }
        }
        return array(
            'freeradius_enabled' => (string)$general->enabled,
            'vlan_assignment_enabled' => (string)$general->vlanassign,
            'fallback_vlan_enabled' => (string)$general->fallbackvlan_enabled,
            'freeradius_status' => trim($statusText),
            'blocked_sync' => trim($sync),
            'counts' => $counts,
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
