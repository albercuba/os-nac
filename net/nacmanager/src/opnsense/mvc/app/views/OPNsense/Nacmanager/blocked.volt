<script>
$(document).ready(function() {
    function reloadBlocked() {
        ajaxGet('/api/nacmanager/devices/search', {status: 'blocked'}, function(data) {
            var tbody = $('#grid-blocked tbody').empty();
            $('#blocked-count').text((data.rows || []).length);
            $.each(data.rows || [], function(_, row) {
                var tr = $('<tr/>');
                tr.append($('<td/>').text(row.mac));
                tr.append($('<td/>').text(row.radius_identity));
                tr.append($('<td/>').text(row.last_seen));
                tr.append($('<td/>').text(row.nas_ip));
                tr.append($('<td/>').text(row.nas_port));
                tr.append($('<td/>').html('<span class="label label-danger">blocked</span>'));
                tr.append($('<td/>').text(row.assigned_vlan));
                var actions = $('<td/>');
                actions.append($('<button class="btn btn-xs btn-success" type="button">{{ lang._('Unblock') }}</button>').click(function() {
                    if (confirm('{{ lang._('Move this device back to Unknown?') }}')) {
                        ajaxCall('/api/nacmanager/devices/unblock/' + row.uuid, {}, function() { reloadBlocked(); });
                    }
                }));
                actions.append(' ');
                actions.append($('<button class="btn btn-xs btn-primary" type="button">{{ lang._('Approve') }}</button>').click(function() {
                    var vlan = prompt('{{ lang._('VLAN ID') }}', row.assigned_vlan || '');
                    if (vlan === null) { return; }
                    var description = prompt('{{ lang._('Description') }}', row.description || '');
                    if (description === null) { return; }
                    ajaxCall('/api/nacmanager/devices/approve/' + row.uuid, {assigned_vlan: vlan, description: description}, function() { reloadBlocked(); });
                }));
                tr.append(actions);
                tbody.append(tr);
            });
        });
    }
    $('#refreshAct').click(reloadBlocked);
    reloadBlocked();
});
</script>

<div class="content-box">
    <div class="col-md-12">
        <h1>{{ lang._('Blocked Devices') }} <span id="blocked-count" class="label label-danger">0</span></h1>
        <p>{{ lang._('Blocked devices are removed from the FreeRADIUS MAC-user allow-list and retained in NAC Manager state.') }}</p>
        <button class="btn btn-primary" id="refreshAct" type="button"><span class="fa fa-refresh"></span> {{ lang._('Refresh') }}</button>
        <br/><br/>
        <table id="grid-blocked" class="table table-condensed table-hover table-striped table-responsive">
            <thead><tr>
                <th>{{ lang._('MAC') }}</th><th>{{ lang._('RADIUS Username') }}</th><th>{{ lang._('Last Seen') }}</th><th>{{ lang._('NAS IP') }}</th>
                <th>{{ lang._('NAS Port') }}</th><th>{{ lang._('Status') }}</th><th>{{ lang._('Last VLAN') }}</th><th>{{ lang._('Actions') }}</th>
            </tr></thead>
            <tbody></tbody>
        </table>
    </div>
</div>
