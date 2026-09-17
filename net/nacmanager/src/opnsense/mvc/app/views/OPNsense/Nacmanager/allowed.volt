<script>
$(document).ready(function() {
    var editRow = null;
    var confirmAction = null;

    function iconButton(style, icon, title) {
        return $('<button class="btn btn-xs btn-' + style + '" type="button" title="' + title + '" aria-label="' + title + '"><span class="fa ' + icon + '"></span></button>');
    }

    function openEditDialog(row) {
        editRow = row;
        $('#edit-device-title').text(row.hostname || row.mac || row.radius_identity || '');
        $('#edit-hostname').text(row.hostname || '');
        $('#edit-mac').text(row.mac || '');
        $('#edit-switch').text(row.switch_name || row.switch_ip || '');
        $('#edit-port').text(row.switch_port || '');
        $('#edit-vlan').val(row.vlan || '');
        $('#edit-description').val(row.description || '');
        $('#edit-enabled').prop('checked', row.enabled == '1');
        $('#edit-validation').hide().text('');
        $('#editDeviceModal').modal('show');
    }

    function saveCurrentDevice() {
        if (editRow === null) {
            return;
        }
        var vlan = $.trim($('#edit-vlan').val());
        var description = $.trim($('#edit-description').val());
        var enabled = $('#edit-enabled').is(':checked') ? '1' : '0';
        if (vlan !== '' && (!/^\d+$/.test(vlan) || parseInt(vlan, 10) < 1 || parseInt(vlan, 10) > 4094)) {
            $('#edit-validation').text('{{ lang._('VLAN must be between 1 and 4094.') }}').show();
            return;
        }
        ajaxCall('/api/nacmanager/allowed/set/' + editRow.uuid, {vlan: vlan, description: description, enabled: enabled}, function() {
            $('#editDeviceModal').modal('hide');
            editRow = null;
            reloadAllowed();
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

    function reloadAllowed() {
        ajaxGet('/api/nacmanager/allowed/search', {}, function(data) {
            var tbody = $('#grid-allowed tbody').empty();
            $('#allowed-count').text((data.rows || []).length);
            $.each(data.rows || [], function(_, row) {
                var tr = $('<tr/>');
                tr.append($('<td/>').html(row.enabled == '1' ? '<span class="label label-success">enabled</span>' : '<span class="label label-default">disabled</span>'));
                tr.append($('<td/>').text(row.description));
                tr.append($('<td/>').text(row.hostname || ''));
                tr.append($('<td/>').text(row.mac));
                tr.append($('<td/>').text(row.radius_identity));
                tr.append($('<td/>').text(row.vlan));
                tr.append($('<td/>').text(row.switch_name || row.switch_ip || ''));
                tr.append($('<td/>').text(row.switch_port || ''));
                tr.append($('<td/>').text(row.port_last_seen || ''));
                var actions = $('<td class="text-nowrap"/>');
                actions.append(iconButton('primary', 'fa-pencil', '{{ lang._('Edit') }}').click(function() {
                    openEditDialog(row);
                }));
                actions.append(' ');
                actions.append(iconButton('warning', 'fa-ban', '{{ lang._('Block') }}').click(function() {
                    openConfirmDialog('{{ lang._('Block device') }}', '{{ lang._('Revoke and block this MAC address?') }}', 'warning', function() {
                        ajaxCall('/api/nacmanager/allowed/block/' + row.uuid, {}, function() { reloadAllowed(); });
                    });
                }));
                actions.append(' ');
                actions.append(iconButton('danger', 'fa-trash', '{{ lang._('Delete') }}').click(function() {
                    openConfirmDialog('{{ lang._('Delete MAC user') }}', '{{ lang._('Delete this FreeRADIUS MAC user?') }}', 'danger', function() {
                        ajaxCall('/api/nacmanager/allowed/delete/' + row.uuid, {}, function() { reloadAllowed(); });
                    });
                }));
                tr.append(actions);
                tbody.append(tr);
            });
        });
    }
    $('#refreshAct').click(reloadAllowed);
    $('#editSaveAct').click(saveCurrentDevice);
    $('#confirmRunAct').click(runConfirmedAction);
    reloadAllowed();
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
        <h1>{{ lang._('Allowed Devices') }} <span id="allowed-count" class="label label-success">0</span></h1>
        <div class="alert alert-info"><span class="fa fa-info-circle"></span> {{ lang._('NAC Manager requires the FreeRADIUS plugin to be installed and configured. This page reads and edits MAC-auth users in FreeRADIUS.') }}</div>

        <button class="btn btn-primary" id="refreshAct" type="button"><span class="fa fa-refresh"></span> {{ lang._('Refresh') }}</button>
        <br/><br/>
        <table id="grid-allowed" class="table table-condensed table-hover table-striped table-responsive">
            <thead><tr>
                <th>{{ lang._('Enabled') }}</th><th>{{ lang._('Description') }}</th><th>{{ lang._('Hostname') }}</th><th>{{ lang._('MAC') }}</th><th>{{ lang._('RADIUS Username') }}</th>
                <th>{{ lang._('VLAN ID') }}</th><th>{{ lang._('Switch') }}</th><th>{{ lang._('Port') }}</th><th>{{ lang._('Port Last Seen') }}</th><th>{{ lang._('Actions') }}</th>
            </tr></thead>
            <tbody></tbody>
        </table>
    </div>
</div>

<div class="modal fade" id="editDeviceModal" tabindex="-1" role="dialog" aria-labelledby="editDeviceLabel">
    <div class="modal-dialog" role="document">
        <div class="modal-content nacmanager-modal">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="{{ lang._('Close') }}"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="editDeviceLabel">{{ lang._('Edit allowed device') }} <small id="edit-device-title"></small></h4>
            </div>
            <div class="modal-body">
                <div id="edit-validation" class="alert alert-danger" style="display:none;"></div>
                <dl class="nac-device-summary">
                    <dt>{{ lang._('Hostname') }}</dt><dd id="edit-hostname"></dd>
                    <dt>{{ lang._('MAC') }}</dt><dd id="edit-mac"></dd>
                    <dt>{{ lang._('Switch') }}</dt><dd id="edit-switch"></dd>
                    <dt>{{ lang._('Port') }}</dt><dd id="edit-port"></dd>
                </dl>
                <div class="checkbox">
                    <label><input type="checkbox" id="edit-enabled" /> {{ lang._('Enabled') }}</label>
                </div>
                <div class="form-group">
                    <label for="edit-vlan">{{ lang._('VLAN ID') }}</label>
                    <input type="text" class="form-control" id="edit-vlan" placeholder="{{ lang._('Optional VLAN ID') }}" />
                </div>
                <div class="form-group">
                    <label for="edit-description">{{ lang._('Description') }}</label>
                    <input type="text" class="form-control" id="edit-description" placeholder="{{ lang._('Device description') }}" />
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button>
                <button type="button" class="btn btn-primary" id="editSaveAct"><span class="fa fa-save"></span> {{ lang._('Save') }}</button>
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
