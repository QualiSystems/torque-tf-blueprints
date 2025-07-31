terraform {
  required_providers {
    torque = {
      source = "QualiTorque/torque"
    }
  }
}

resource "torque_introspection_resource" "scratch_org_details" {
  display_name = var.vm_name
  image        = "https://raw.githubusercontent.com/QualiTorque/Torque-Samples/refs/heads/main/icons/openshift-logo.svg"
  introspection_data = {
    "VM Name": var.vm_name
    "Namespace": var.namespace
    "IP Address": var.ip
    "User": var.user
    "Password": var.password
  }
}
