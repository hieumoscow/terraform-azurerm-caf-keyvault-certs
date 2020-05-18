output "principal_id" {
  value = azurerm_user_assigned_identity.msi.principal_id
}

# {for x in range(0,9) : x => x}
output "secret_ids" {
  value = length(var.certificates) == 0 ? {} : { for i, cert in azurerm_key_vault_certificate.certificates.* : var.certificates[i] => {#azurerm_key_vault_certificate.certificates.*
      secret_id = cert.secret_id
    }
  }
}

output "identity_ids" {
  value = [azurerm_user_assigned_identity.msi.id]
}