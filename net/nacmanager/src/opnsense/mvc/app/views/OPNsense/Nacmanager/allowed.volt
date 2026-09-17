<script>
$(document).ready(function() {
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
                var actions = $('<td/>');
                actions.append($('<button class="btn btn-xs btn-primary" type="button">{{ lang._('Edit') }}</button>').click(function() {
                    var vlan = prompt('{{ lang._('VLAN ID') }}', row.vlan || '');
                    if (vlan === null) { return; }
                    var description = prompt('{{ lang._('Description') }}', row.description || '');
                    if (description === null) { return; }
                    var enabled = confirm('{{ lang._('Click OK to keep/enable this device. Click Cancel to disable it.') }}') ? '1' : '0';
                    ajaxCall('/api/nacmanager/allowed/set/' + row.uuid, {vlan: vlan, description: description, enabled: enabled}, function() { reloadAllowed(); });
                }));
                actions.append(' ');
                actions.append($('<button class="btn btn-xs btn-warning" type="button">{{ lang._('Block') }}</button>').click(function() {
                    if (confirm('{{ lang._('Revoke and block this MAC address?') }}')) {
                        ajaxCall('/api/nacmanager/allowed/block/' + row.uuid, {}, function() { reloadAllowed(); });
                    }
                }));
                actions.append(' ');
                actions.append($('<button class="btn btn-xs btn-danger" type="button">{{ lang._('Delete') }}</button>').click(function() {
                    if (confirm('{{ lang._('Delete this FreeRADIUS MAC user?') }}')) {
                        ajaxCall('/api/nacmanager/allowed/delete/' + row.uuid, {}, function() { reloadAllowed(); });
                    }
                }));
                tr.append(actions);
                tbody.append(tr);
            });
        });
    }
    $('#refreshAct').click(reloadAllowed);
    reloadAllowed();
});
</script>

<div class="content-box">
    <div class="col-md-12">
        <h1>{{ lang._('Allowed Devices') }} <span id="allowed-count" class="label label-success">0</span></h1>
        <p>{{ lang._('This page reads 12-hex-digit MAC-auth endpoint users directly from the FreeRADIUS user model. Normal username/password accounts are not shown.') }}</p>
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
