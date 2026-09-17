<script>
$(document).ready(function() {
    function yesNoLabel(value, yesStyle, noStyle) {
        var enabled = value == '1' || value === true || value === 'yes';
        return '<span class="label label-' + (enabled ? yesStyle : noStyle) + '">' + (enabled ? '{{ lang._('Enabled') }}' : '{{ lang._('Disabled') }}') + '</span>';
    }

    function okLabel(ok) {
        return '<span class="label label-' + (ok ? 'success' : 'danger') + '">' + (ok ? '{{ lang._('OK') }}' : '{{ lang._('Error') }}') + '</span>';
    }

    function setCount(id, value) {
        $(id).text(value || 0);
    }

    function renderRuntimeStatus(radiusStatus, blockedSync) {
        var running = /\bis running\b/i.test(radiusStatus || '');
        var pid = /pid\s+(\d+)/i.exec(radiusStatus || '');
        $('#radius-status-label').html('<span class="label label-' + (running ? 'success' : 'danger') + '">' + (running ? '{{ lang._('Running') }}' : '{{ lang._('Not running') }}') + '</span>');
        $('#radius-status-detail').text(pid ? '{{ lang._('Process ID') }}: ' + pid[1] : (radiusStatus || '{{ lang._('No status output returned.') }}'));

        var blocked = /blocked=(\d+)/i.exec(blockedSync || '');
        if (blocked) {
            $('#blocked-sync-label').html('<span class="label label-success">{{ lang._('Synced') }}</span>');
            $('#blocked-sync-detail').text(blocked[1] + ' {{ lang._('blocked device reject rule(s) are currently synced to FreeRADIUS.') }}');
        } else {
            $('#blocked-sync-label').html('<span class="label label-default">{{ lang._('Unknown') }}</span>');
            $('#blocked-sync-detail').text(blockedSync || '{{ lang._('No sync output returned.') }}');
        }
    }

    function renderWarnings(warnings) {
        var box = $('#warnings-box').empty();
        if (!warnings || warnings.length === 0) {
            box.append($('<div class="alert alert-success"/>').html('<span class="fa fa-check"></span> {{ lang._('No warnings detected.') }}'));
            return;
        }
        $.each(warnings, function(_, warning) {
            box.append($('<div class="alert alert-warning"/>').text(warning));
        });
    }

    function renderLogs(logs) {
        var tbody = $('#logs-table tbody').empty();
        if (!logs || logs.length === 0) {
            tbody.append($('<tr/>').append($('<td colspan="5" class="text-muted"/>').text('{{ lang._('No log sources reported.') }}')));
            return;
        }
        $.each(logs, function(_, row) {
            var tr = $('<tr/>');
            tr.append($('<td/>').text(row.path || ''));
            tr.append($('<td/>').html(row.exists ? '<span class="label label-success">{{ lang._('Found') }}</span>' : '<span class="label label-default">{{ lang._('Missing') }}</span>'));
            tr.append($('<td/>').text(row.size || 0));
            tr.append($('<td/>').text(row.candidate_events_in_tail || 0));
            tr.append($('<td/>').text(row.error || ''));
            tbody.append(tr);
        });
    }

    function renderDetectOutput(output) {
        var match = /processed=(\d+)\s+discovered=(\d+)(?:\s+ignored=(\d+))?/.exec(output || '');
        if (match) {
            $('#detect-summary').html(
                '<span class="label label-info">{{ lang._('Log events read') }}: ' + match[1] + '</span> ' +
                '<span class="label label-success">{{ lang._('New devices') }}: ' + match[2] + '</span> ' +
                '<span class="label label-default">{{ lang._('802.1X events ignored') }}: ' + (match[3] || 0) + '</span>'
            );
            $('#detect-help').text('{{ lang._('MAC-auth events can create Unknown Devices. 802.1X/PEAP events are counted but ignored because MAC approval cannot fix certificate or EAP credential failures.') }}');
            $('#detect-output').text(output);
            $('#detect-output-row').show();
            return;
        }
        $('#detect-summary').html('<span class="label label-default">{{ lang._('Not run yet') }}</span>');
        $('#detect-help').text('{{ lang._('Click Scan FreeRADIUS logs to process new MAC-auth log entries.') }}');
        $('#detect-output').text(output || '');
        $('#detect-output-row').toggle(!!output);
    }

    function reloadDiagnostics() {
        ajaxGet('/api/nacmanager/diagnostics/status', {}, function(data) {
            var counts = data.counts || {};
            var diagnostics = data.diagnostics || {};
            setCount('#unknown-count', counts.unknown);
            setCount('#allowed-count', counts.allowed);
            setCount('#blocked-count', counts.blocked);
            setCount('#mac-user-count', counts.mac_users);
            setCount('#duplicate-count', counts.duplicate_mac_users);

            $('#freeradius-enabled').html(yesNoLabel(data.freeradius_enabled, 'success', 'default'));
            $('#vlan-enabled').html(yesNoLabel(data.vlan_assignment_enabled, 'success', 'warning'));
            $('#fallback-enabled').html(yesNoLabel(data.fallback_vlan_enabled, 'warning', 'success'));
            $('#diagnostics-ok').html(okLabel(diagnostics.diagnostics_ok !== false));
            $('#config-exists').html(okLabel(diagnostics.config_exists === true));
            $('#authorize-exists').html(okLabel(diagnostics.authorize_exists === true));
            $('#detect-state').text((diagnostics.detect_state_exists ? '{{ lang._('Exists') }}' : '{{ lang._('Not created yet') }}') + (diagnostics.detect_state_path ? ' — ' + diagnostics.detect_state_path : ''));
            renderRuntimeStatus(data.freeradius_status || diagnostics.radius_status || '', data.blocked_sync || '');
            $('#diagnostics-error').text(diagnostics.diagnostics_error || '');
            $('#diagnostics-error-row').toggle(!!diagnostics.diagnostics_error);
            renderWarnings(data.warnings || []);
            renderLogs(diagnostics.logs || []);
        });
    }

    $('#refreshAct').click(reloadDiagnostics);
    $('#detectAct').click(function() {
        $('#detect-summary').html('<span class="label label-info">{{ lang._('Running') }}</span>');
        $('#detect-help').text('{{ lang._('Scanning configured FreeRADIUS log sources...') }}');
        $('#detect-output-row').hide();
        ajaxCall('/api/nacmanager/diagnostics/detect', {}, function(data) {
            renderDetectOutput(data.response || '');
            reloadDiagnostics();
        });
    });
    renderDetectOutput('');
    reloadDiagnostics();
});
</script>

<style>
.nac-health-list dd { padding-bottom: 5px; }
.nac-runtime-item { margin-bottom: 14px; }
.nac-runtime-item:last-child { margin-bottom: 0; }
.nac-runtime-detail { margin: 6px 0 0; color: #777; }
.nac-detect-help { margin: 8px 0 0; color: #777; }
</style>

<div class="content-box">
    <div class="col-md-12">
        <h1>{{ lang._('NAC Manager Diagnostics') }}</h1>
        <div class="alert alert-info"><span class="fa fa-info-circle"></span> {{ lang._('NAC Manager requires the FreeRADIUS plugin to be installed and configured. Install os-freeradius first, then configure FreeRADIUS clients and MAC-auth users through this plugin.') }}</div>
        <p>{{ lang._('Review FreeRADIUS integration, detected device counts, blocked-device synchronization, and log sources used by NAC Manager.') }}</p>
        <button class="btn btn-primary" id="refreshAct" type="button"><span class="fa fa-refresh"></span> {{ lang._('Refresh') }}</button>
        <button class="btn btn-default" id="detectAct" type="button"><span class="fa fa-search"></span> {{ lang._('Scan FreeRADIUS logs') }}</button>
        <br/><br/>

        <div class="row">
            <div class="col-md-2 col-sm-4">
                <div class="panel panel-default text-center">
                    <div class="panel-heading">{{ lang._('Unknown') }}</div>
                    <div class="panel-body"><h2 id="unknown-count">0</h2></div>
                </div>
            </div>
            <div class="col-md-2 col-sm-4">
                <div class="panel panel-default text-center">
                    <div class="panel-heading">{{ lang._('Allowed') }}</div>
                    <div class="panel-body"><h2 id="allowed-count">0</h2></div>
                </div>
            </div>
            <div class="col-md-2 col-sm-4">
                <div class="panel panel-default text-center">
                    <div class="panel-heading">{{ lang._('Blocked') }}</div>
                    <div class="panel-body"><h2 id="blocked-count">0</h2></div>
                </div>
            </div>
            <div class="col-md-2 col-sm-4">
                <div class="panel panel-default text-center">
                    <div class="panel-heading">{{ lang._('MAC Users') }}</div>
                    <div class="panel-body"><h2 id="mac-user-count">0</h2></div>
                </div>
            </div>
            <div class="col-md-2 col-sm-4">
                <div class="panel panel-default text-center">
                    <div class="panel-heading">{{ lang._('Duplicates') }}</div>
                    <div class="panel-body"><h2 id="duplicate-count">0</h2></div>
                </div>
            </div>
        </div>

        <div id="warnings-box"></div>

        <div class="row">
            <div class="col-md-6">
                <div class="panel panel-default">
                    <div class="panel-heading"><span class="fa fa-cogs"></span> {{ lang._('Service health') }}</div>
                    <div class="panel-body">
                        <dl class="dl-horizontal nac-health-list">
                            <dt>{{ lang._('FreeRADIUS') }}</dt><dd id="freeradius-enabled"></dd>
                            <dt>{{ lang._('VLAN assignment') }}</dt><dd id="vlan-enabled"></dd>
                            <dt>{{ lang._('Fallback VLAN') }}</dt><dd id="fallback-enabled"></dd>
                            <dt>{{ lang._('Diagnostics') }}</dt><dd id="diagnostics-ok"></dd>
                            <dt>{{ lang._('Config file') }}</dt><dd id="config-exists"></dd>
                            <dt>{{ lang._('Authorize file') }}</dt><dd id="authorize-exists"></dd>
                            <dt>{{ lang._('Detect cursor') }}</dt><dd id="detect-state"></dd>
                        </dl>
                        <div id="diagnostics-error-row" class="alert alert-danger" style="display:none;"><strong>{{ lang._('Diagnostics error') }}:</strong> <span id="diagnostics-error"></span></div>
                    </div>
                </div>
            </div>
            <div class="col-md-6">
                <div class="panel panel-default">
                    <div class="panel-heading"><span class="fa fa-server"></span> {{ lang._('Runtime output') }}</div>
                    <div class="panel-body">
                        <div class="nac-runtime-item">
                            <strong>{{ lang._('FreeRADIUS service') }}</strong><br/>
                            <span id="radius-status-label"></span>
                            <p id="radius-status-detail" class="nac-runtime-detail"></p>
                        </div>
                        <div class="nac-runtime-item">
                            <strong>{{ lang._('Blocked device synchronization') }}</strong><br/>
                            <span id="blocked-sync-label"></span>
                            <p id="blocked-sync-detail" class="nac-runtime-detail"></p>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <div class="panel panel-default">
            <div class="panel-heading"><span class="fa fa-file-text-o"></span> {{ lang._('FreeRADIUS log sources') }}</div>
            <div class="panel-body">
                <p class="text-muted">{{ lang._('Candidate events include MAC Auth/MAB events and classified 802.1X events in the recent log tail. 802.1X events are not added as approvable Unknown Devices.') }}</p>
                <table id="logs-table" class="table table-condensed table-hover table-striped table-responsive">
                    <thead><tr>
                        <th>{{ lang._('Path') }}</th><th>{{ lang._('Status') }}</th><th>{{ lang._('Size') }}</th><th>{{ lang._('Candidate Events') }}</th><th>{{ lang._('Error') }}</th>
                    </tr></thead>
                    <tbody></tbody>
                </table>
            </div>
        </div>

        <div class="panel panel-default">
            <div class="panel-heading"><span class="fa fa-search"></span> {{ lang._('Last detection run') }}</div>
            <div class="panel-body">
                <p id="detect-summary"></p>
                <p id="detect-help" class="nac-detect-help"></p>
                <div id="detect-output-row" style="display:none;">
                    <strong>{{ lang._('Raw output') }}</strong>
                    <pre id="detect-output"></pre>
                </div>
            </div>
        </div>
    </div>
</div>
