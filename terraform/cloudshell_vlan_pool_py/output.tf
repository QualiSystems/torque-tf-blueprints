output "vlan_id" {
    value = jsondecode(data.local_file.vlan_id.content).result
}
