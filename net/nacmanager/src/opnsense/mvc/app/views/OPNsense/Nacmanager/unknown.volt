<script>
$(document).ready(function() {
    function reloadUnknown() {
        ajaxGet('/api/nacmanager/devices/search', {status: 'unknown'}, function(data) {
            var tbody = $('#grid-unknown tbody').empty();
            $('#unknown-count').text((data.rows || []).length);
            $.each(data.rows || [], function(_, row) {
                var tr = $('<tr/>');
                tr.append($('<td/>').text(row.mac));
                tr.append($('<td/>').text(row.radius_identity));
                tr.append($('<td/>').text(row.first_seen));
                tr.append($('<td/>').text(row.last_seen));
                tr.append($('<td/>').text(row.nas_ip));
                tr.append($('<td/>').text(row.nas_port));
                tr.append($('<td/>').text(row.switch_name || row.switch_ip || ''));
                tr.append($('<td/>').text(row.switch_port || row.nas_port || ''));
                tr.append($('<td/>').html('<span class="label label-warning">unknown</span>')); 
                tr.append($('<td/>').text(row.assigned_vlan));
                var actions = $('<td/>');
                actions.append($('<button class="btn btn-xs btn-primary" type="button">{{ lang._('Approve') }}</button>').click(function() {
                    var vlan = prompt('{{ lang._('VLAN ID') }}', row.assigned_vlan || '');
                    if (vlan === null) { return; }
                    var description = prompt('{{ lang._('Description') }}', row.description || '');
                    if (description === null) { return; }
                    ajaxCall('/api/nacmanager/devices/approve/' + row.uuid, {assigned_vlan: vlan, description: description}, function() { reloadUnknown(); });
                }));
                actions.append(' ');
                actions.append($('<button class="btn btn-xs btn-warning" type="button">{{ lang._('Block') }}</button>').click(function() {
                    if (confirm('{{ lang._('Block this MAC address?') }}')) {
                        ajaxCall('/api/nacmanager/devices/block/' + row.uuid, {}, function() { reloadUnknown(); });
                    }
                }));
                actions.append(' ');
                actions.append($('<button class="btn btn-xs btn-default" type="button">{{ lang._('Delete') }}</button>').click(function() {
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
                <th>{{ lang._('MAC') }}</th><th>{{ lang._('RADIUS Username') }}</th><th>{{ lang._('First Seen') }}</th><th>{{ lang._('Last Seen') }}</th>
                <th>{{ lang._('NAS IP') }}</th><th>{{ lang._('NAS Port') }}</th><th>{{ lang._('Switch') }}</th><th>{{ lang._('Port') }}</th><th>{{ lang._('Status') }}</th><th>{{ lang._('Desired VLAN') }}</th><th>{{ lang._('Actions') }}</th>
            </tr></thead>
            <tbody></tbody>
        </table>
    </div>
</div>
