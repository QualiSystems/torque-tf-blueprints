output "vsphere_virtual_machine_name" {
  value = vsphere_virtual_machine.vm.name
}

output "vsphere_virtual_machine_ip" {
  description = "The primary IP address of the VM"
  value       = local.is_windows ? vsphere_virtual_machine.vm.guest_ip_addresses[0] : length(vsphere_virtual_machine.vm.guest_ip_addresses) > 0 ? vsphere_virtual_machine.vm.guest_ip_addresses[0] : ""

}

output "remote_access_link" {
  description = "Remote access HTTP link if QualiX is enabled"
  value       = var.qualix_ip != "" ? module.remote_access_link.http_link : null
}