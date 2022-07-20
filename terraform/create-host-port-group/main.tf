provider "vsphere" {
  user           = var.username
  password       = var.password
  vsphere_server = var.hostname
  version        = "=1.15.0"
  # If you have a self-signed cert
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

data "vsphere_host" "host" {
  name          = var.host_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_host_port_group" "pg" {
  name                = var.port_group_name
  host_system_id      = data.vsphere_host.host.id
  virtual_switch_name = var.virtual_switch_name
  vlan_id = var.vlan_id
  allow_promiscuous = true
}
