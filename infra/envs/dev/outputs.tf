output "resource_group_name" {
  description = "Name of the deployed resource group"
  value       = azurerm_resource_group.rg.name
}

output "static_website_endpoint" {
  description = "Primary endpoint of the static website"
  value       = azurerm_storage_account.web.primary_web_endpoint
}

output "storage_account_name" {
  description = "Name of the storage account hosting the static website"
  value       = azurerm_storage_account.web.name
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.kv.vault_uri
}
