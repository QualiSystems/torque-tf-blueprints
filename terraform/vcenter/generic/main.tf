terraform {
  required_providers {
    vsphere = {
      source = "hashicorp/vsphere"
      version = "~>2.0"
    }
  }
}

provider "vsphere" {
  user           = var.vc_username
  password       = var.vc_password
  vsphere_server = var.vc_address
  # If you have a self-signed cert
  allow_unverified_ssl = true
}

# data
data "vsphere_datacenter" "datacenter" {
  name = var.vc_dc_name
}

data "vsphere_datastore" "datastore" {
  name          = var.vc_ds_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.compute_cluster_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  count         = var.network_name != "" ? 1 : 0
  name          = var.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vm_template_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

locals {
  env_id              = reverse(split("/", var.vm_folder_path))[0]
  selected_network_id = var.network_name != "" ? data.vsphere_network.network.id : data.vsphere_virtual_machine.template.network_interfaces[0].network_id
  is_windows          = can(regex("windows", lower(data.vsphere_virtual_machine.template.guest_id)))
  protocol            = local.is_windows ? "rdp" : "ssh"
  connection_port     = local.is_windows ? 3389 : 22
  enable_qualix_link  = var.qualix_ip != "" ? 1 : 0
}

# resources
resource "vsphere_virtual_machine" "vm" {
  name                        = var.vm_name == "" ? "${var.vm_template_name}-${local.env_id}" : "${var.vm_name}-${local.env_id}"
  folder                      = var.vm_folder_path
  datastore_id                = data.vsphere_datastore.datastore.id
  resource_pool_id            = var.resource_pool_id != "" ? var.resource_pool_id : data.vsphere_compute_cluster.cluster.resource_pool_id
  num_cpus                    = data.vsphere_virtual_machine.template.num_cpus
  memory                      = data.vsphere_virtual_machine.template.memory
  guest_id                    = data.vsphere_virtual_machine.template.guest_id
  scsi_type                   = data.vsphere_virtual_machine.template.scsi_type
  efi_secure_boot_enabled     = data.vsphere_virtual_machine.template.efi_secure_boot_enabled
  firmware                    = data.vsphere_virtual_machine.template.firmware
  wait_for_guest_ip_timeout   = var.wait_for_ip
  wait_for_guest_net_timeout  = var.wait_for_net

  network_interface {
    network_id = local.selected_network_id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label             = "disk0"
    size              = data.vsphere_virtual_machine.template.disks.0.size
    thin_provisioned  = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  clone {
      template_uuid = data.vsphere_virtual_machine.template.id
      linked_clone  = var.is_linked_clone
    customize {
      network_interface {
        ipv4_address    = var.requested_vm_address
        ipv4_netmask    = 24
        # ipv4_gateway    = "192.168.51.1"
        # dns_server_list = ["8.8.8.8"]

      }
      dynamic "linux_options" {
        for_each = local.is_windows ? [] : [1]
        content {
          host_name = "QualiLinux-${local.env_id}"
          domain    = "local"
        }
      }

      dynamic "windows_options" {
        for_each = local.is_windows ? [1] : []
        content {
          computer_name  = "QualiWin-${local.env_id}"
          admin_password = "Password1"
        }
      }
    }
  } 
}

module "remote_access_link" {
    count             = local.enable_qualix_link
    source            = "../qualix_link_maker"
    qualix_ip         = var.qualix_ip
    protocol          = local.protocol
    connection_port   = local.connection_port
    target_ip_address = var.requested_vm_address
    target_username   = "Administrator"
    target_password   = "Password1"
}
