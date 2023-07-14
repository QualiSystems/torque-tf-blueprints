terraform {
  required_providers {
    http = {
      source = "hashicorp/http"
      version = "3.4.0"
    }
  }
}

locals {
  method = "POST"
  auth_url = "http://${var.hostname}:${var.port}/ResourceManagerApiService/Logon"
  checkout_vlan = "http://${var.hostname}:${var.port}/ResourceManagerApiService/CheckoutFromPool"
  release_vlan = "http://${var.hostname}:${var.port}/ResourceManagerApiService/ReleaseFromPool"
  get_vlan_from_snadbox_data = "http://${var.hostname}:${var.port}/ResourceManagerApiService/GetSandboxData"
  save_vlan_to_snadbox_data = "http://${var.hostname}:${var.port}/ResourceManagerApiService/SetSandboxData"
  token_regex = "<Token Token=\"(.*?)\"/>"
  vlan_id_regex = "<Items>(.*?)</Items>"
  existing_vlan_regex = "<SandboxDataKeyValue Key=\\\"${var.torque_sandbox_id}\\\" Value=\\\"(.*?)\\\""
  general_heades = {
    "Content-Type": "text/xml", 
    "Accept": "*/*", 
    "ClientTimeZoneId": "UTC", 
    "DateTimeFormat": "MM/dd/yyyy HH:mm", 
    "Host": "${var.hostname}:${var.port}", 
  }
  auth_header = {"Authorization": "MachineName=${var.hostname}:${var.port};Token="}
  pool_id = "global"
  vlan_id_request = jsonencode({
    "type": "NextAvailableNumericFromRange", 
    "poolId": "global", 
    "reservationId": "${var.sandbox_id}", 
    "ownerId": "${var.username}", 
    "isolation": "${var.isolation}", 
    "requestedRange": {
      "start": var.vlan_min, 
      "end": var.vlan_max
    }
  })
  verify_vlan_exists = "\"${var.torque_sandbox_id}\"\\s*Value=\"\\d+\""
  has_torque_sandbox_id = "<SandboxDataKeyValue Key=\\\"(${var.torque_sandbox_id})\\\""
}

data "http" "auth" {
  url = local.auth_url
  method = local.method

  request_headers = merge(local.general_heades, local.auth_header)
  request_body = "<Logon><username>${var.username}</username><password>${var.password}</password><domainName>${var.domain}</domainName></Logon>"
}

data "http" "get_vlan" {
  depends_on = [data.http.auth]
  url = local.get_vlan_from_snadbox_data
  method = local.method
  request_headers = merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"})
  request_body = "<GetSandboxData><reservationId>${var.sandbox_id}</reservationId></GetSandboxData>"
}

data "http" "reserve_vlan" {
  count = can(regex(local.verify_vlan_exists, data.http.get_vlan.response_body)) ? 0 : 1
  depends_on = [data.http.auth]
  url = local.checkout_vlan
  method = local.method
  request_headers = merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"})
  request_body = "<CheckoutFromPool><selectionCriteriaJson>${local.vlan_id_request}</selectionCriteriaJson></CheckoutFromPool>"
}

data "http" "store_vlan" {
  depends_on = [data.http.auth, data.http.reserve_vlan]
  count = length(data.http.reserve_vlan) > 0 ? 1 : 0
  url = local.save_vlan_to_snadbox_data
  method = local.method
  request_headers = merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"})
  request_body = "<SetSandboxData><reservationId>${var.sandbox_id}</reservationId><sandboxDataKeyValues><SandboxDataKeyValue><Key>${var.torque_sandbox_id}</Key><Value>${regexall(local.vlan_id_regex, data.http.reserve_vlan[0].response_body)[0][0]}</Value></SandboxDataKeyValue></sandboxDataKeyValues></SetSandboxData>"
}

resource "null_resource" "destroy_vlan_reservation" {
  depends_on = [data.http.auth, data.http.get_vlan]

  triggers = {
    link = "curl -s -X POST ${local.release_vlan} ${join(" ", [for k,v in merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"}) : format ("-H '%s: %s'", k, v)])} -d '<ReleaseFromPool><values><string>${can(regex(local.verify_vlan_exists, data.http.get_vlan.response_body)) ? regexall(local.existing_vlan_regex, data.http.get_vlan.response_body)[0][0] : regexall(local.vlan_id_regex, data.http.reserve_vlan[0].response_body)[0][0]}</string></values><poolId>${local.pool_id}</poolId><reservationId>${var.sandbox_id}</reservationId><ownerId>${var.username}</ownerId></ReleaseFromPool>'"
    erase_link = "curl -s -X POST ${local.save_vlan_to_snadbox_data} ${join(" ", [for k,v in merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"}) : format ("-H '%s: %s'", k, v)])} -d '<SetSandboxData><reservationId>${var.sandbox_id}</reservationId><sandboxDataKeyValues><SandboxDataKeyValue><Key>${var.torque_sandbox_id}</Key><Value></Value></SandboxDataKeyValue></sandboxDataKeyValues></SetSandboxData>'"
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.link
    on_failure = fail
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.erase_link
  }
}

output "vlan_id" {
  value = can(regex(local.verify_vlan_exists, data.http.get_vlan.response_body)) ? regexall(local.existing_vlan_regex, data.http.get_vlan.response_body)[0][0] : regexall(local.vlan_id_regex, data.http.reserve_vlan[0].response_body)[0][0]
}
