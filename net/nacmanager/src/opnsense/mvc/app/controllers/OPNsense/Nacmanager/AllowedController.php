<?php

namespace OPNsense\Nacmanager;

use OPNsense\Base\IndexController;

class AllowedController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Nacmanager/allowed');
    }
}
