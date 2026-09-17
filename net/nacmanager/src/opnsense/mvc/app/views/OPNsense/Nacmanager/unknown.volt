<script>
$(document).ready(function() {
    var approveRow = null;

    function iconButton(style, icon, title) {
        return $('<button class="btn btn-xs btn-' + style + '" type="button" title="' + title + '" aria-label="' + title + '"><span class="fa ' + icon + '"></span></button>');
    }

    function openApproveDialog(row) {
        approveRow = row;
        $('#approve-device-title').text(row.hostname || row.mac || row.radius_identity || '');
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
                    if (confirm('{{ lang._('Block this MAC address?') }}')) {
                        ajaxCall('/api/nacmanager/devices/block/' + row.uuid, {}, function() { reloadUnknown(); });
                    }
                }));
                actions.append(' ');
                actions.append(iconButton('default', 'fa-trash', '{{ lang._('Delete') }}').click(function() {
                    if (confirm('{{ lang._('Delete this discovery record?') }}')) {
                        ajaxCall('/api/nacmanager/devices/delete/' + row.uuid, {}, function() { reloadUnknown(); });
                    }
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
    reloadUnknown();
});
</script>

<div class="content-box">
    <div class="col-md-12">
        <h1>{{ lang._('Unknown Devices') }} <span id="unknown-count" class="label label-warning">0</span></h1>
        <p>{{ lang._('Newest unauthorized MAC-auth attempts detected from FreeRADIUS activity appear first.') }}</p>
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
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="{{ lang._('Close') }}"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="approveDeviceLabel">{{ lang._('Approve device') }} <small id="approve-device-title"></small></h4>
            </div>
            <div class="modal-body">
                <div id="approve-validation" class="alert alert-danger" style="display:none;"></div>
                <dl class="dl-horizontal">
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
