locals {
  response_file = "${path.module}/vlan-${var.torque_sandbox_id}"
  python_script_file_path = "${path.module}/python_script.py"
  python_script = <<PYTHON
import json

from cloudshell.api.cloudshell_api import CloudShellAPISession, SandboxDataKeyValue

def get_vlan_id(api):
    data = api.GetSandboxData("${var.sandbox_id}")
    if data:
        for item in data.SandboxDataKeyValues:
            if item.Value == "${var.torque_sandbox_id}":
                return item.Key
    request = {"type": "NextAvailableNumericFromRange",
              "poolId": "${var.pool_id}",
              "reservationId": "${var.sandbox_id}",
              "ownerId": "${var.torque_sandbox_id}",
              "isolation": 'Exclusive',
              "requestedRange": None
              }
    vlan = None
    for vlan_range in "${var.vlan_ranges}".split(","):
        vlan_range = vlan_range.split("-")
        request["requestedRange"] = {"start": int(vlan_range[0]), "end": int(vlan_range[1])}
        try:
            vlan_response = api.CheckoutFromPool(selectionCriteriaJson=json.dumps(request))
            if vlan_response and vlan_response.Items:
                vlan = vlan_response.Items[0]
                break
        except Exception as e:
            continue

    if not vlan: raise Exception("No VLANs available within the specified vlan ranges")
    api.SetSandboxData("${var.sandbox_id}", [SandboxDataKeyValue(Key=vlan, Value="${var.torque_sandbox_id}")])
    return vlan

api = CloudShellAPISession(host="${var.hostname}", username="${var.username}", password="${var.password}", domain="${var.domain}", port=${var.port})
vlan = get_vlan_id(api)
print({"result": vlan})
with open("${local.response_file}", "w+") as f:
    f.write(json.dumps({"result": vlan}))
PYTHON
  destroy_python_script_file_path = "${path.module}/destroy_python_script.py"
  destroy_python_script = <<PYTHON
from cloudshell.api.cloudshell_api import CloudShellAPISession, SandboxDataKeyValue

api = CloudShellAPISession(host="${var.hostname}", username="${var.username}", password="${var.password}", domain="${var.domain}", port=${var.port})
data = api.GetSandboxData("${var.sandbox_id}")
if data:
    for item in data.SandboxDataKeyValues:
        if item.Value == "${var.torque_sandbox_id}":
            api.ReleaseFromPool(values=[item.Key], poolId="${var.pool_id}", reservationId="${var.sandbox_id}", ownerId="${var.torque_sandbox_id}")
            api.SetSandboxData("${var.sandbox_id}", [SandboxDataKeyValue(Key=item.Key, Value="")])
            break
PYTHON
}

resource "local_file" "python_script_file" {
  filename = "${local.python_script_file_path}"
  content  = local.python_script
}

resource "local_file" "destroy_python_script_file" {
  filename = "${local.destroy_python_script_file_path}"
  content  = local.destroy_python_script
}

resource "null_resource" "vlan_reservation" {
  depends_on = [local_file.python_script_file]
  triggers = {
    python_script = local_file.python_script_file.filename
  }
  provisioner "local-exec" {
    command = "python3 -m pip install cloudshell-automation-api"
    on_failure = fail
  }
  provisioner "local-exec" {
    command = "python3 ${self.triggers.python_script}"
    on_failure = fail
  }
}

resource "null_resource" "vlan_destroy" {
  depends_on = [local_file.destroy_python_script_file]
  triggers = { 
    destroy_python_script = local_file.destroy_python_script_file.filename
    vlan_id_file = local.response_file
  }

  provisioner "local-exec" {
    when    = destroy
    command = "python3 ${self.triggers.destroy_python_script}"
    on_failure = fail
  }
  provisioner "local-exec" {
    when    = destroy
    command = "rm ${self.triggers.vlan_id_file}"
    on_failure = fail
  }
}

data "local_file" "vlan_id" {
  depends_on = [local_file.python_script_file, null_resource.vlan_reservation]
  filename = local.response_file
}

