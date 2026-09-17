<script>
$(document).ready(function() {
    var approveRow = null;
    var confirmAction = null;

    function iconButton(style, icon, title) {
        return $('<button class="btn btn-xs btn-' + style + '" type="button" title="' + title + '" aria-label="' + title + '"><span class="fa ' + icon + '"></span></button>');
    }

    function openApproveDialog(row) {
        approveRow = row;
        $('#approve-hostname').text(row.hostname || '');
        $('#approve-mac').text(row.mac || '');
        $('#approve-switch').text(row.switch_name || row.switch_ip || '');
        $('#approve-port').text(row.switch_port || row.nas_port || '');
        $('#approve-vlan').val(row.assigned_vlan || '');
        $('#approve-description').val(row.description || row.hostname || '');
        $('#approve-validation').hide().text('');
        $('#approveDeviceModal').modal('show');
    }

    function approveCurrentDevice() {
        if (approveRow === null) {
            return;
        }
        var vlan = $.trim($('#approve-vlan').val());
        var description = $.trim($('#approve-description').val());
        if (vlan !== '' && (!/^\d+$/.test(vlan) || parseInt(vlan, 10) < 1 || parseInt(vlan, 10) > 4094)) {
            $('#approve-validation').text('{{ lang._('VLAN must be between 1 and 4094.') }}').show();
            return;
        }
        ajaxCall('/api/nacmanager/devices/approve/' + approveRow.uuid, {assigned_vlan: vlan, description: description}, function() {
            $('#approveDeviceModal').modal('hide');
            approveRow = null;
            reloadUnknown();
        });
    }

    function openConfirmDialog(title, message, style, callback) {
        confirmAction = callback;
        $('#confirm-title').text(title);
        $('#confirm-message').text(message);
        $('#confirmRunAct').removeClass('btn-primary btn-warning btn-danger btn-success').addClass('btn-' + style);
        $('#confirmDeviceModal').modal('show');
    }

    function runConfirmedAction() {
        if (confirmAction !== null) {
            confirmAction();
        }
        confirmAction = null;
        $('#confirmDeviceModal').modal('hide');
    }

    function reloadUnknown() {
        ajaxGet('/api/nacmanager/devices/search', {status: 'unknown'}, function(data) {
            var tbody = $('#grid-unknown tbody').empty();
            $('#unknown-count').text((data.rows || []).length);
            $.each(data.rows || [], function(_, row) {
                var tr = $('<tr/>');
                tr.append($('<td/>').text(row.mac));
                tr.append($('<td/>').text(row.hostname || ''));
                tr.append($('<td/>').text(row.radius_identity));
                tr.append($('<td/>').text(row.first_seen));
                tr.append($('<td/>').text(row.last_seen));
                tr.append($('<td/>').text(row.switch_name || row.switch_ip || ''));
                tr.append($('<td/>').text(row.switch_port || row.nas_port || ''));
                tr.append($('<td/>').html('<span class="label label-warning">unknown</span>'));
                tr.append($('<td/>').text(row.assigned_vlan));
                var actions = $('<td class="text-nowrap"/>');
                actions.append(iconButton('primary', 'fa-check', '{{ lang._('Approve') }}').click(function() {
                    openApproveDialog(row);
                }));
                actions.append(' ');
                actions.append(iconButton('warning', 'fa-ban', '{{ lang._('Block') }}').click(function() {
                    openConfirmDialog('{{ lang._('Block device') }}', '{{ lang._('Block this MAC address?') }}', 'warning', function() {
                        ajaxCall('/api/nacmanager/devices/block/' + row.uuid, {}, function() { reloadUnknown(); });
                    });
                }));
                actions.append(' ');
                actions.append(iconButton('default', 'fa-trash', '{{ lang._('Delete') }}').click(function() {
                    openConfirmDialog('{{ lang._('Delete discovery record') }}', '{{ lang._('Delete this discovery record?') }}', 'danger', function() {
                        ajaxCall('/api/nacmanager/devices/delete/' + row.uuid, {}, function() { reloadUnknown(); });
                    });
                }));
                tr.append(actions);
                tbody.append(tr);
            });
        });
    }
    $('#refreshAct').click(reloadUnknown);
    $('#detectAct').click(function() {
        ajaxCall('/api/nacmanager/diagnostics/detect', {}, function() { reloadUnknown(); });
    });
    $('#approveSaveAct').click(approveCurrentDevice);
    $('#confirmRunAct').click(runConfirmedAction);
    reloadUnknown();
});
</script>

<style>
.nacmanager-modal .modal-header { border-bottom: 0; padding: 18px 24px 8px; }
.nacmanager-modal .modal-body { padding: 8px 24px 18px; }
.nacmanager-modal .modal-footer { border-top: 0; padding: 12px 24px 20px; }
.nac-device-summary { margin: 0 0 18px; }
.nac-device-summary dt { clear: left; float: left; width: 90px; text-align: left; font-weight: 600; }
.nac-device-summary dd { margin-left: 100px; margin-bottom: 4px; }
.nac-confirm-message { margin: 0; }
</style>

<div class="content-box">
    <div class="col-md-12">
        <h1>{{ lang._('Unknown Devices') }} <span id="unknown-count" class="label label-warning">0</span></h1>
        <div class="alert alert-info"><span class="fa fa-info-circle"></span> {{ lang._('NAC Manager requires the FreeRADIUS plugin to be installed and configured. Approvals create or update MAC-auth users in FreeRADIUS.') }}</div>

        <button class="btn btn-primary" id="refreshAct" type="button"><span class="fa fa-refresh"></span> {{ lang._('Refresh') }}</button>
        <button class="btn btn-default" id="detectAct" type="button"><span class="fa fa-search"></span> {{ lang._('Scan FreeRADIUS logs') }}</button>
        <br/><br/>
        <table id="grid-unknown" class="table table-condensed table-hover table-striped table-responsive">
            <thead><tr>
                <th>{{ lang._('MAC') }}</th><th>{{ lang._('Hostname') }}</th><th>{{ lang._('RADIUS Username') }}</th><th>{{ lang._('First Seen') }}</th><th>{{ lang._('Last Seen') }}</th>
                <th>{{ lang._('Switch') }}</th><th>{{ lang._('Port') }}</th><th>{{ lang._('Status') }}</th><th>{{ lang._('Desired VLAN') }}</th><th>{{ lang._('Actions') }}</th>
            </tr></thead>
            <tbody></tbody>
        </table>
    </div>
</div>

<div class="modal fade" id="approveDeviceModal" tabindex="-1" role="dialog" aria-labelledby="approveDeviceLabel">
    <div class="modal-dialog" role="document">
        <div class="modal-content nacmanager-modal">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="{{ lang._('Close') }}"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="approveDeviceLabel">{{ lang._('Approve device') }}</h4>
            </div>
            <div class="modal-body">
                <div id="approve-validation" class="alert alert-danger" style="display:none;"></div>
                <dl class="nac-device-summary">
                    <dt>{{ lang._('Hostname') }}</dt><dd id="approve-hostname"></dd>
                    <dt>{{ lang._('MAC') }}</dt><dd id="approve-mac"></dd>
                    <dt>{{ lang._('Switch') }}</dt><dd id="approve-switch"></dd>
                    <dt>{{ lang._('Port') }}</dt><dd id="approve-port"></dd>
                </dl>
                <div class="form-group">
                    <label for="approve-vlan">{{ lang._('VLAN ID') }}</label>
                    <input type="text" class="form-control" id="approve-vlan" placeholder="{{ lang._('Optional VLAN ID') }}" />
                    <span class="help-block">{{ lang._('Enter a VLAN between 1 and 4094, or leave empty for no VLAN assignment.') }}</span>
                </div>
                <div class="form-group">
                    <label for="approve-description">{{ lang._('Description') }}</label>
                    <input type="text" class="form-control" id="approve-description" placeholder="{{ lang._('Device description') }}" />
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button>
                <button type="button" class="btn btn-primary" id="approveSaveAct"><span class="fa fa-check"></span> {{ lang._('Approve') }}</button>
            </div>
        </div>
    </div>
</div>

<div class="modal fade" id="confirmDeviceModal" tabindex="-1" role="dialog" aria-labelledby="confirmDeviceLabel">
    <div class="modal-dialog" role="document">
        <div class="modal-content nacmanager-modal">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="{{ lang._('Close') }}"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="confirmDeviceLabel"><span id="confirm-title"></span></h4>
            </div>
            <div class="modal-body">
                <p id="confirm-message" class="nac-confirm-message"></p>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button>
                <button type="button" class="btn btn-warning" id="confirmRunAct">{{ lang._('Continue') }}</button>
            </div>
        </div>
    </div>
</div>
