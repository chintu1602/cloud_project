output "public_ip" {
  value       = azurerm_public_ip.this.ip_address
  description = "Application Gateway public IP address"
}

output "public_ip_fqdn" {
  value       = azurerm_public_ip.this.fqdn
  description = "Application Gateway public IP FQDN"
}

output "id" {
  value       = azurerm_application_gateway.this.id
  description = "Application Gateway ID"
}
