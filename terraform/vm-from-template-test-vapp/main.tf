provider "vsphere" {
  user           = var.username
  password       = var.password
  vsphere_server = var.hostname
  # If you have a self-signed cert
  allow_unverified_ssl = true
}

locals {
# String to list 
  interfaces = [
    for iface in split(",", var.networks):
    trimspace(iface)
  ]
# List to map
interface_map = {
   for i, val in local.interfaces:
	i => val
  }
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

data "vsphere_datastore" "ds" {
  name          = var.datastore_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.compute_cluster_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  for_each = toset( local.interfaces )
  name          = each.key
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name = var.virtual_machine_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "vm" {
  name             = var.virtual_machine_name
  datastore_id     = data.vsphere_datastore.ds.id
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  guest_id = data.vsphere_virtual_machine.template.guest_id
  folder = var.virtual_machine_folder
  wait_for_guest_ip_timeout = var.wait_for_ip
  wait_for_guest_net_timeout = var.wait_for_net
  
  dynamic "network_interface" {
      for_each = local.interface_map
        content {
    network_id = data.vsphere_network.network[network_interface.value].id
          adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
        }
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    linked_clone = var.linked_clone
  }
  dynamic "disk" {
    for_each = data.vsphere_virtual_machine.template.disks
    content {
      unit_number      = disk.key
      label            = disk.value.label
      size             = disk.value.size
      thin_provisioned = disk.value.thin_provisioned
      eagerly_scrub    = false
    }
  }
  vapp {
    properties = {
      "guestinfo.hostname"     = "quali-test-centos",
    }
  }
}

