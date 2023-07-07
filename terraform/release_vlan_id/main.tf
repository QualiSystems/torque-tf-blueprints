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
  release_vlan = "http://${var.hostname}:${var.port}/ResourceManagerApiService/ReleaseFromPool"

  token_regex = "<Token Token=\"(.*?)\"/>"
  general_heades = {
    "Content-Type": "text/xml", 
    "Accept": "*/*", 
    "ClientTimeZoneId": "UTC", 
    "DateTimeFormat": "MM/dd/yyyy HH:mm", 
    "Host": "${var.hostname}:${var.port}", 
  }
  auth_header = {"Authorization": "MachineName=${var.hostname}:${var.port};Token="}
  pool_id = "global"
}

data "http" "auth" {
  url = local.auth_url
  method = local.method

  request_headers = merge(local.general_heades, local.auth_header)
  request_body = "<Logon><username>${var.username}</username><password>${var.password}</password><domainName>Global</domainName></Logon>"
}

data "http" "release_vlan" {
  depends_on = [data.http.auth]
  url = local.release_vlan
  method = local.method
  request_headers = merge(local.general_heades, {"Authorization": "MachineName=${var.hostname}:${var.port};Token=${regexall(local.token_regex, data.http.auth.response_body)[0][0]}"})
  request_body = "<ReleaseFromPool><values><string>${var.vlan_id}</string></values><poolId>${local.pool_id}</poolId><reservationId>${var.sandbox_id}</reservationId><ownerId>${var.username}</ownerId></ReleaseFromPool>"
}

output "http_code" {
    value = data.http.release_vlan.status_code
}


