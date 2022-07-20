variable "hostname" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

variable "datacenter_name" {
  type = string
  default = "Sandbox vCenter"
}

variable "host_name" {
  type = string
  default = "alexander.g"
}

variable "port_group_name" {
  type = string
  default = "PG26"
}

variable "virtual_switch_name" {
  type = string
  default = "vSwitch1"
}

variable "vlan_id" {
  type = number
  default = 26
}

