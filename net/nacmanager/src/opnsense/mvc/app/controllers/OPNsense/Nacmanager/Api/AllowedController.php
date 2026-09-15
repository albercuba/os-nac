<?php

namespace OPNsense\Nacmanager\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Config;
use OPNsense\Freeradius\General as FreeRADIUSGeneral;
use OPNsense\Freeradius\User as FreeRADIUSUser;
use OPNsense\Nacmanager\Nacmanager;

class AllowedController extends ApiControllerBase
{
    private function isMacIdentity($value)
    {
        return preg_match('/^[0-9A-Fa-f]{12}$/', (string)$value) === 1;
    }

    private function normalizeMac($value)
    {
        $identity = strtoupper(preg_replace('/[^0-9A-Fa-f]/', '', (string)$value));
        return preg_match('/^[0-9A-F]{12}$/', $identity) ? $identity : null;
    }

    private function displayMac($identity)
    {
        return implode(':', str_split(strtoupper($identity), 2));
    }

    private function now()
    {
        return gmdate('c');
    }

    private function findDeviceByIdentity(Nacmanager $model, $identity)
    {
        foreach ($model->devices->device->iterateItems() as $uuid => $node) {
            if (strtoupper((string)$node->radius_identity) === $identity) {
                return array($uuid, $node);
            }
        }
        return array(null, null);
    }

    private function reconfigureFreeRADIUS()
    {
        $general = new FreeRADIUSGeneral();
        $backend = new Backend();
        $backend->configdRun('freeradius stop');
        $backend->configdRun('template reload OPNsense/Freeradius');
        $backend->configdRun('nacmanager sync');
        if ($general->enabled->__toString() == '1') {
            $backend->configdRun('freeradius start');
        }
    }

    private function findRadiusUser(FreeRADIUSUser $model, $uuid)
    {
        return $model->getNodeByReference('users.user.' . $uuid);
    }

    public function searchAction()
    {
        $rows = array();
        $radius = new FreeRADIUSUser();
        foreach ($radius->users->user->iterateItems() as $uuid => $node) {
            $identity = strtoupper((string)$node->username);
            if (!$this->isMacIdentity($identity)) {
                continue;
            }
            $rows[] = array(
                'uuid' => $uuid,
                'enabled' => (string)$node->enabled,
                'description' => (string)$node->description,
                'mac' => $this->displayMac($identity),
                'radius_identity' => $identity,
                'vlan' => (string)$node->vlan,
            );
        }
        usort($rows, function ($a, $b) {
            return strcmp($a['mac'], $b['mac']);
        });
        return array('rows' => $rows, 'rowCount' => count($rows), 'total' => count($rows), 'current' => 1);
    }

    public function getAction($uuid = null)
    {
        $radius = new FreeRADIUSUser();
        if ($uuid !== null) {
            $node = $this->findRadiusUser($radius, $uuid);
            if ($node !== null && $this->isMacIdentity((string)$node->username)) {
                return array('allowed' => array(
                    'uuid' => $uuid,
                    'enabled' => (string)$node->enabled,
                    'description' => (string)$node->description,
                    'mac' => $this->displayMac((string)$node->username),
                    'radius_identity' => strtoupper((string)$node->username),
                    'vlan' => (string)$node->vlan,
                ));
            }
        }
        return array();
    }

    public function setAction($uuid)
    {
        if (!$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $radius = new FreeRADIUSUser();
        $node = $this->findRadiusUser($radius, $uuid);
        if ($node === null || !$this->isMacIdentity((string)$node->username)) {
            return array('result' => 'not found');
        }
        $vlan = $this->request->getPost('vlan', null, (string)$node->vlan);
        if ($vlan !== '' && (!ctype_digit((string)$vlan) || (int)$vlan < 1 || (int)$vlan > 4094)) {
            return array('result' => 'failed', 'validations' => array('vlan' => 'VLAN must be 1-4094'));
        }
        $enabled = $this->request->getPost('enabled', null, (string)$node->enabled) == '1' ? '1' : '0';
        $node->enabled = $enabled;
        $node->description = $this->request->getPost('description', null, (string)$node->description);
        if ($vlan !== '') {
            $node->vlan = (string)$vlan;
        }
        $valMsgs = $radius->performValidation();
        if ($valMsgs->count() > 0) {
            $result = array('result' => 'failed', 'validations' => array());
            foreach ($valMsgs as $field => $msg) {
                $result['validations'][$msg->getField()] = $msg->getMessage();
            }
            return $result;
        }
        $radius->serializeToConfig();

        $identity = strtoupper((string)$node->username);
        $model = new Nacmanager();
        list($deviceUuid, $device) = $this->findDeviceByIdentity($model, $identity);
        if ($device === null) {
            $device = $model->devices->device->add();
            $device->mac = $this->displayMac($identity);
            $device->radius_identity = $identity;
            $device->first_seen = $this->now();
        }
        $device->status = $enabled == '1' ? 'allowed' : 'unknown';
        $device->assigned_vlan = (string)$node->vlan;
        $device->description = (string)$node->description;
        $device->updated_at = $this->now();
        $model->serializeToConfig();
        Config::getInstance()->save();
        $this->reconfigureFreeRADIUS();
        error_log('nacmanager: edited allowed device ' . $identity);
        return array('result' => 'saved');
    }

    public function deleteAction($uuid)
    {
        if (!$this->request->isDelete() && !$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $radius = new FreeRADIUSUser();
        $node = $this->findRadiusUser($radius, $uuid);
        if ($node === null || !$this->isMacIdentity((string)$node->username)) {
            return array('result' => 'not found');
        }
        $identity = strtoupper((string)$node->username);
        $radius->users->user->del($uuid);
        $radius->serializeToConfig();
        $model = new Nacmanager();
        list($deviceUuid, $device) = $this->findDeviceByIdentity($model, $identity);
        if ($device === null) {
            $device = $model->devices->device->add();
            $device->mac = $this->displayMac($identity);
            $device->radius_identity = $identity;
            $device->first_seen = $this->now();
        }
        $device->status = 'unknown';
        $device->updated_at = $this->now();
        $model->serializeToConfig();
        Config::getInstance()->save();
        $this->reconfigureFreeRADIUS();
        error_log('nacmanager: revoked allowed device ' . $identity);
        return array('result' => 'deleted');
    }

    public function blockAction($uuid)
    {
        if (!$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $radius = new FreeRADIUSUser();
        $node = $this->findRadiusUser($radius, $uuid);
        if ($node === null || !$this->isMacIdentity((string)$node->username)) {
            return array('result' => 'not found');
        }
        $identity = strtoupper((string)$node->username);
        $vlan = (string)$node->vlan;
        $desc = (string)$node->description;
        $radius->users->user->del($uuid);
        $radius->serializeToConfig();
        $model = new Nacmanager();
        list($deviceUuid, $device) = $this->findDeviceByIdentity($model, $identity);
        if ($device === null) {
            $device = $model->devices->device->add();
            $device->mac = $this->displayMac($identity);
            $device->radius_identity = $identity;
            $device->first_seen = $this->now();
        }
        $device->status = 'blocked';
        $device->auth_result = 'reject';
        $device->assigned_vlan = $vlan;
        $device->description = $desc;
        $device->updated_at = $this->now();
        $model->serializeToConfig();
        Config::getInstance()->save();
        $this->reconfigureFreeRADIUS();
        error_log('nacmanager: moved allowed device to blocked ' . $identity);
        return array('result' => 'saved');
    }
}
