output "resource_group_name" {
  description = "The resource group created"
  value       = azurerm_resource_group.rg.name
}

output "vm_public_ip" {
  description = "Public IP address of the VM"
  value       = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  description = "Suggested ssh command to connect to the VM"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}
