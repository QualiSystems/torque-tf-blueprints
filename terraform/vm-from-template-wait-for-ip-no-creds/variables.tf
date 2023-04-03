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
  default = "Sandbox"
}

variable "datastore_name" {
  type = string
  default = "Lab-datastore"
}

variable "compute_cluster_name" {
  type = string
  default = "Sandbox Cluster"
}

variable "wait_for_ip" {
  type = number
  default = 120
} 

variable "wait_for_net" {
  type = number
  default = 120
} 

variable "networks" {
  type        = string
  description = "Provided interfaces"
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
  default = "Costya.Y"
}

variable "linked_clone" {
  type = bool
  default = false
}
