<?php

namespace OPNsense\Nacmanager;

use OPNsense\Base\IndexController;

class DiagnosticsController extends IndexController
{
    public function indexAction()
    {
        $this->view->pick('OPNsense/Nacmanager/diagnostics');
    }
}
