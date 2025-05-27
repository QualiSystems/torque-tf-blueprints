variable "vc_address" {
  type = string
}

variable "vc_username" {
  type = string
}

variable "vc_password" {
  type = string
}

variable "vc_dc_name" {
  type    = string
  default = "Sandbox vCenter"
}

variable "vc_ds_name" {
  type    = string
  default = "SB-DS2"
}

variable "compute_cluster_name" {
  type = string
  default = "Sandbox Cluster"
}

variable "network_name" {
  type        = string
  default     = ""
  description = "Optional. Name of the network to attach to the VM."
}

variable "vm_template_name" {
  type = string
}

variable "vm_name" {
  type    = string
  default = "vm started by a script"
}

variable "vm_folder_path" {
  type = string
  default = "Alexey.B"
}

variable "requested_vm_address" {}

variable "resource_pool_id" {}

variable "is_linked_clone" {
  type        = bool
  default     = false
  description = "Whether to use linked clone or full clone"
}

variable "qualix_ip" {
  type        = string
  description = "IP of the QualiX Server (empty to disable remote access)"
  default     = ""
}