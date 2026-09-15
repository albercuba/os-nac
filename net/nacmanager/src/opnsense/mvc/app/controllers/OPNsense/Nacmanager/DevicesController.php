<?php

namespace OPNsense\Nacmanager;

use OPNsense\Base\IndexController;

class DevicesController extends IndexController
{
    public function unknownAction()
    {
        $this->view->pick('OPNsense/Nacmanager/unknown');
    }

    public function blockedAction()
    {
        $this->view->pick('OPNsense/Nacmanager/blocked');
    }
}
