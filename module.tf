# issue with destroy & recreate https://github.com/terraform-providers/terraform-provider-acme/issues/68#issuecomment-508735169
# https://community.letsencrypt.org/t/unable-to-regenerate-certificate-with-terraform/80275/2
# ACME Let's Encrypt only works on public domain

resource "tls_private_key" "private_key" {
  count = length(var.certificates)

  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  count = length(var.certificates)

  account_key_pem = tls_private_key.private_key[count.index].private_key_pem
  email_address   = var.email
}

resource "random_string" "passwords" {
  count = length(var.certificates)

  length = 16
}
resource "acme_certificate" "certificate" {
  count = length(var.certificates)

  account_key_pem          = acme_registration.reg[count.index].account_key_pem
  common_name              = var.certificates[count.index]
  certificate_p12_password = random_string.passwords[count.index].result

  dns_challenge {
    provider = "azure"
    config = {
      AZURE_RESOURCE_GROUP = var.domain_resource_group_name
    }
  }
}



resource "azurecaf_naming_convention" "caf_name_kv" {
  name          = var.akv_config.name
  prefix        = var.prefix != "" ? var.prefix : null
  resource_type = "azurerm_key_vault"
  convention    = var.convention
}


resource "azurerm_key_vault" "akv" {
  name                = azurecaf_naming_convention.caf_name_kv.result
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
  sku_name            = var.akv_config.sku_name

  enabled_for_disk_encryption     = lookup(var.akv_config.akv_features, "enabled_for_disk_encryption", null)
  enabled_for_deployment          = lookup(var.akv_config.akv_features, "enabled_for_deployment", null)
  enabled_for_template_deployment = lookup(var.akv_config.akv_features, "enabled_for_template_deployment", null)
  soft_delete_enabled             = lookup(var.akv_config.akv_features, "soft_delete_enabled", null)
}

# rover identity
resource "azurerm_key_vault_access_policy" "rover" {

  key_vault_id = azurerm_key_vault.akv.id
  tenant_id    = local.tenant_id
  object_id    = local.object_id

  key_permissions = []

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete"
  ]

  certificate_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Import",
    "Purge"
  ]
  # backup, create, delete, deleteissuers, get, getissuers, import, 
  # list, listissuers, managecontacts, manageissuers, purge, recover, restore, setissuers and update.
}


resource "azurerm_key_vault_certificate" "certificates" {
  depends_on = [azurerm_key_vault_access_policy.rover]
  count      = length(var.certificates)

  name         = trim(replace(replace(var.certificates[count.index], ".", "-"), "*", ""),"-")
  key_vault_id = azurerm_key_vault.akv.id

  certificate {
    contents = acme_certificate.certificate[count.index].certificate_p12
    password = random_string.passwords[count.index].result #"testpassword"
  }

  certificate_policy {
    issuer_parameters {
      name = "Unknown"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "az keyvault certificate purge --vault-name ${azurerm_key_vault.akv.name} --name ${self.name}"
  }
}

resource "azurerm_user_assigned_identity" "msi" {
  resource_group_name = var.resource_group_name
  location            = var.location
  name                = "keyvault-cert-msi"
}

resource "azurerm_key_vault_access_policy" "msi" {

  key_vault_id = azurerm_key_vault.akv.id
  tenant_id    = local.tenant_id
  object_id    = azurerm_user_assigned_identity.msi.principal_id

  key_permissions = []

  secret_permissions = [
    "Get",
    "List",
    "Set",
    "Delete",

  ]

  certificate_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Import",
    "Purge"
  ]
  # backup, create, delete, deleteissuers, get, getissuers, import, 
  # list, listissuers, managecontacts, manageissuers, purge, recover, restore, setissuers and update.
}
