<script>
$(document).ready(function() {
    function reloadDiagnostics() {
        ajaxGet('/api/nacmanager/diagnostics/status', {}, function(data) {
            $('#freeradius-enabled').text(data.freeradius_enabled == '1' ? 'yes' : 'no');
            $('#vlan-enabled').text(data.vlan_assignment_enabled == '1' ? 'yes' : 'no');
            $('#fallback-enabled').text(data.fallback_vlan_enabled == '1' ? 'yes' : 'no');
            $('#radius-status').text(data.freeradius_status || 'unknown');
            $('#blocked-sync').text(data.blocked_sync || 'not run');
            $('#counts').text(JSON.stringify(data.counts || {}));
        });
    }
    $('#refreshAct').click(reloadDiagnostics);
    $('#detectAct').click(function() {
        ajaxCall('/api/nacmanager/diagnostics/detect', {}, function(data) {
            $('#detect-output').text(data.response || '');
            reloadDiagnostics();
        });
    });
    reloadDiagnostics();
});
</script>

<div class="content-box">
    <div class="col-md-12">
        <h1>{{ lang._('NAC Manager Diagnostics') }}</h1>
        <button class="btn btn-primary" id="refreshAct" type="button"><span class="fa fa-refresh"></span> {{ lang._('Refresh') }}</button>
        <button class="btn btn-default" id="detectAct" type="button"><span class="fa fa-search"></span> {{ lang._('Scan FreeRADIUS logs') }}</button>
        <br/><br/>
        <dl class="dl-horizontal">
            <dt>{{ lang._('FreeRADIUS enabled') }}</dt><dd id="freeradius-enabled"></dd>
            <dt>{{ lang._('VLAN assignment enabled') }}</dt><dd id="vlan-enabled"></dd>
            <dt>{{ lang._('Fallback VLAN enabled') }}</dt><dd id="fallback-enabled"></dd>
            <dt>{{ lang._('Service status') }}</dt><dd><pre id="radius-status"></pre></dd>
            <dt>{{ lang._('Blocked sync') }}</dt><dd><pre id="blocked-sync"></pre></dd>
            <dt>{{ lang._('Counts') }}</dt><dd><pre id="counts"></pre></dd>
            <dt>{{ lang._('Detect output') }}</dt><dd><pre id="detect-output"></pre></dd>
        </dl>
    </div>
</div>
