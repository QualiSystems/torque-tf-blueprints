variable "username" {
  type = string
}

variable "password" {
  type = string
  sensitive = true
}

variable "hostname" {
  type = string
}

variable "port" {
  type = number
  default = 8029
}

variable "domain" {
  type = string
  default = "Global"
}

variable "sandbox_id" {
  type = string

  validation {
    condition = can(regex("^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$", var.sandbox_id))
    error_message = "The sandbox_id must be a valid Cloudshell sandbox id GUID"
  }
}

variable "isolation" {
  type = string
  default = "Exclusive"
}

variable "vlan_min" {
  type = number
  default = 2
}

variable "vlan_max" {
  type = number
  default = 4048
}

variable "torque_sandbox_id" {
  type = string
}