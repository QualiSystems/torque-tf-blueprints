terraform {
  required_providers {
    torque = {
      source = "QualiTorque/torque"
    }
  }
}

resource "torque_introspection_resource" "scratch_org_details" {
  display_name = var.vm_name
  image        = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/OpenShift-LogoType.svg/1200px-OpenShift-LogoType.svg.png"
  introspection_data = {
    "VM Name": var.vm_name
    "Namespace": var.namespace
    "IP Address": var.ip
    "User": var.user
    "Password": var.password
  }
}