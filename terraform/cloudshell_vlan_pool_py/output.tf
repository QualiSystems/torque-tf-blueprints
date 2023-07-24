output "vlan_id" {
  # value = data.external.policy_document.result
    value = jsondecode(data.local_file.vlan_id.content).result

}
