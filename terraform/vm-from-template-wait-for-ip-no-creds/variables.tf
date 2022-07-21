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

variable "datastore_name" {
  type = string
  default = "SB-DS2"
}

variable "compute_cluster_name" {
  type = string
  default = "Sandbox Cluster"
}

variable "network_name0" {
  type = string
  default = "Local"
}

variable "wait_for_ip" {
  type = number
  default = 120
} 

variable "wait_for_net" {
  type = number
  default = 120
} 

variable "network_name1" {
  type = string
  default = "Local"
}

variable "network_name2" {
  type = string
  default = "Local"
}

variable "network_name3" {
  type = string
  default = "Local"
}

variable "virtual_machine_template_name" {
  type = string
}

variable "virtual_machine_name" {
  type = string
  default = "vm started by a script"
}

variable "virtual_machine_folder" {
  type = string
  default = "alexander.g"
}

