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
  token_regex = "<Token Token=\"(.*?)\"/>"
  vlan_id_regex = "<Items>(.*?)</Items>"
  general_heades = {
    "Content-Type": "text/xml", 
    "Accept": "*/*", 
    "ClientTimeZoneId": "UTC", 
    "DateTimeFormat": "MM/dd/yyyy HH:mm", 
    "Host": "${var.hostname}:${var.port}", 
  }
  # auth_header = {"Authorization": "MachineName=QS-IL-LT-COSTAY:8029;Token="}
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
}

data "http" "auth" {
  url = local.auth_url
  method = local.method

  request_headers = merge(local.general_heades, local.auth_header)
  request_body = "<Logon><username>${var.username}</username><password>${var.password}</password><domainName>${var.domain}</domainName></Logon>"
}

data "http" "reserve_vlan" {
  depends_on = [data.http.auth]
  url = local.checkout_vlan
  method = local.method
  request_headers = merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"})
  request_body = "<CheckoutFromPool><selectionCriteriaJson>${local.vlan_id_request}</selectionCriteriaJson></CheckoutFromPool>"
}

output "vlan_id" {
    value = regexall(local.vlan_id_regex, data.http.reserve_vlan.response_body)[0][0]
}


