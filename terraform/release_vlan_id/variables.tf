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
  default = "43c2681f-54ad-4057-a184-24cf9c726d56"
}

variable "vlan_id" {
  type = string
}