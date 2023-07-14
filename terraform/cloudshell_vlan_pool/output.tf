output "vlan_id" {
  value = can(regex(local.verify_vlan_exists, data.http.get_vlan.response_body)) ? regexall(local.existing_vlan_regex, data.http.get_vlan.response_body)[0][0] : regexall(local.vlan_id_regex, data.http.reserve_vlan[0].response_body)[0][0]
}
