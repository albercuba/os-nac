<?php

namespace OPNsense\Nacmanager\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Config;
use OPNsense\Freeradius\General as FreeRADIUSGeneral;
use OPNsense\Freeradius\User as FreeRADIUSUser;
use OPNsense\Nacmanager\Nacmanager;

class DevicesController extends ApiMutableModelControllerBase
{
    protected static $internalModelName = 'Nacmanager';
    protected static $internalModelClass = '\\OPNsense\\Nacmanager\\Nacmanager';

    private function now()
    {
        return gmdate('c');
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

    private function isMacIdentity($value)
    {
        return preg_match('/^[0-9A-Fa-f]{12}$/', (string)$value) === 1;
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

    private function freeradiusUsers()
    {
        return new FreeRADIUSUser();
    }

    private function findRadiusUsersByIdentity(FreeRADIUSUser $model, $identity)
    {
        $matches = array();
        foreach ($model->users->user->iterateItems() as $uuid => $node) {
            if (strtoupper((string)$node->username) === $identity) {
                $matches[$uuid] = $node;
            }
        }
        return $matches;
    }

    private function findRadiusUserByIdentity(FreeRADIUSUser $model, $identity)
    {
        $matches = $this->findRadiusUsersByIdentity($model, $identity);
        foreach ($matches as $uuid => $node) {
            return array($uuid, $node);
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

    private function rowsByStatus($status)
    {
        $rows = array();
        $model = new Nacmanager();
        foreach ($model->devices->device->iterateItems() as $uuid => $node) {
            if ((string)$node->status !== $status) {
                continue;
            }
            $rows[] = array(
                'uuid' => $uuid,
                'mac' => (string)$node->mac,
                'radius_identity' => (string)$node->radius_identity,
                'first_seen' => (string)$node->first_seen,
                'last_seen' => (string)$node->last_seen,
                'nas_ip' => (string)$node->nas_ip,
                'nas_port' => (string)$node->nas_port,
                'calling_station_id' => (string)$node->calling_station_id,
                'auth_result' => (string)$node->auth_result,
                'status' => (string)$node->status,
                'assigned_vlan' => (string)$node->assigned_vlan,
                'description' => (string)$node->description,
                'notes' => (string)$node->notes,
            );
        }
        usort($rows, function ($a, $b) {
            return strcmp($b['last_seen'], $a['last_seen']);
        });
        return $rows;
    }

    public function searchAction()
    {
        $status = $this->request->get('status', null, 'unknown');
        if (!in_array($status, array('unknown', 'blocked', 'allowed'))) {
            $status = 'unknown';
        }
        $rows = $this->rowsByStatus($status);
        return array('rows' => $rows, 'rowCount' => count($rows), 'total' => count($rows), 'current' => 1);
    }

    public function getAction($uuid = null)
    {
        $model = new Nacmanager();
        if ($uuid !== null) {
            $node = $model->getNodeByReference('devices.device.' . $uuid);
            if ($node !== null) {
                return array('device' => $node->getNodes());
            }
        }
        return array();
    }

    public function ingestAction()
    {
        if (!$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $identity = $this->normalizeMac($this->request->getPost('radius_identity', null, $this->request->getPost('mac')));
        if ($identity === null) {
            return array('result' => 'failed', 'validations' => array('mac' => 'Invalid MAC identity'));
        }

        $radius = $this->freeradiusUsers();
        list($userUuid, $userNode) = $this->findRadiusUserByIdentity($radius, $identity);
        $status = $userNode !== null && $userNode->enabled->__toString() == '1' ? 'allowed' : 'unknown';

        $model = new Nacmanager();
        list($uuid, $node) = $this->findDeviceByIdentity($model, $identity);
        if ($node === null) {
            $node = $model->devices->device->add();
            $node->mac = $this->displayMac($identity);
            $node->radius_identity = $identity;
            $node->first_seen = $this->now();
            error_log('nacmanager: device discovered ' . $identity);
        }
        $node->last_seen = $this->now();
        $node->nas_ip = $this->request->getPost('nas_ip', null, '');
        $node->nas_port = $this->request->getPost('nas_port', null, '');
        $node->calling_station_id = $this->request->getPost('calling_station_id', null, '');
        $node->auth_result = $this->request->getPost('auth_result', null, 'reject');
        if ((string)$node->status !== 'blocked') {
            $node->status = $status;
        }
        $model->serializeToConfig();
        Config::getInstance()->save();
        return array('result' => 'saved');
    }

    public function approveAction($uuid)
    {
        if (!$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $model = new Nacmanager();
        $node = $model->getNodeByReference('devices.device.' . $uuid);
        if ($node === null) {
            return array('result' => 'not found');
        }
        $identity = $this->normalizeMac((string)$node->radius_identity);
        $vlan = $this->request->getPost('assigned_vlan', null, (string)$node->assigned_vlan);
        if ($identity === null) {
            return array('result' => 'failed', 'validations' => array('mac' => 'Invalid MAC identity'));
        }
        if ($vlan !== '' && (!ctype_digit((string)$vlan) || (int)$vlan < 1 || (int)$vlan > 4094)) {
            return array('result' => 'failed', 'validations' => array('assigned_vlan' => 'VLAN must be 1-4094'));
        }

        $radius = $this->freeradiusUsers();
        $matches = $this->findRadiusUsersByIdentity($radius, $identity);
        if (count($matches) > 1) {
            return array(
                'result' => 'failed',
                'validations' => array('radius_identity' => 'Duplicate FreeRADIUS MAC users exist for this identity. Remove duplicates in FreeRADIUS before approving.')
            );
        }
        $userUuid = null;
        $userNode = null;
        foreach ($matches as $matchUuid => $matchNode) {
            $userUuid = $matchUuid;
            $userNode = $matchNode;
        }
        if ($userNode === null) {
            $userNode = $radius->users->user->add();
        }
        $userNode->enabled = '1';
        $userNode->username = $identity;
        $userNode->password = $identity;
        $userNode->passwordencryption = 'Cleartext-Password';
        $userNode->description = $this->request->getPost('description', null, (string)$node->description);
        if ($vlan !== '') {
            $userNode->vlan = (string)$vlan;
            $node->assigned_vlan = (string)$vlan;
        }
        $valMsgs = $radius->performValidation();
        if ($valMsgs->count() > 0) {
            $result = array('result' => 'failed', 'validations' => array());
            foreach ($valMsgs as $field => $msg) {
                $result['validations'][$msg->getField()] = $msg->getMessage();
            }
            return $result;
        }
        $node->status = 'allowed';
        $node->description = $this->request->getPost('description', null, (string)$node->description);
        $node->updated_at = $this->now();
        $radius->serializeToConfig();
        $model->serializeToConfig();
        Config::getInstance()->save();
        $this->reconfigureFreeRADIUS();
        error_log('nacmanager: approved ' . $identity);
        return array('result' => 'saved');
    }

    public function blockAction($uuid)
    {
        if (!$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $model = new Nacmanager();
        $node = $model->getNodeByReference('devices.device.' . $uuid);
        if ($node === null) {
            return array('result' => 'not found');
        }
        $identity = $this->normalizeMac((string)$node->radius_identity);
        if ($identity === null) {
            return array('result' => 'failed');
        }
        $radius = $this->freeradiusUsers();
        list($userUuid, $userNode) = $this->findRadiusUserByIdentity($radius, $identity);
        if ($userNode !== null) {
            $radius->users->user->del($userUuid);
            $radius->serializeToConfig();
        }
        $node->status = 'blocked';
        $node->auth_result = 'reject';
        $node->updated_at = $this->now();
        $model->serializeToConfig();
        Config::getInstance()->save();
        $this->reconfigureFreeRADIUS();
        error_log('nacmanager: blocked ' . $identity);
        return array('result' => 'saved');
    }

    public function unblockAction($uuid)
    {
        if (!$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $model = new Nacmanager();
        $node = $model->getNodeByReference('devices.device.' . $uuid);
        if ($node === null) {
            return array('result' => 'not found');
        }
        $node->status = 'unknown';
        $node->updated_at = $this->now();
        $model->serializeToConfig();
        Config::getInstance()->save();
        $this->reconfigureFreeRADIUS();
        error_log('nacmanager: unblocked ' . (string)$node->radius_identity);
        return array('result' => 'saved');
    }

    public function deleteAction($uuid)
    {
        if (!$this->request->isDelete() && !$this->request->isPost()) {
            return array('result' => 'failed');
        }
        $model = new Nacmanager();
        if ($model->devices->device->del($uuid)) {
            $model->serializeToConfig();
            Config::getInstance()->save();
            error_log('nacmanager: deleted device record ' . $uuid);
            return array('result' => 'deleted');
        }
        return array('result' => 'not found');
    }
}
