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
  common_name              = var.certificates[count.index]   #"helloworld.petcafsandpit789.com"
  certificate_p12_password = random_string.passwords[count.index].result #"testpassword"

  dns_challenge {
    provider = "azure"
    config = {
      # AZURE_SUBSCRIPTION_ID = "0d942dd6-0ff2-4601-a9da-0ae82683948b"
      # AZURE_CLIENT_ID       = "b68e0201-da17-4150-84a1-18b6b8b1855f"
      # AZURE_CLIENT_SECRET   = "G4lpCyzTS2201xqatpYAbajVUAX5NPPTJmfjgj52dgLk6POHJSMMny5xtZNjCdA3coZfNsswy57O7z37n3AbThgRd7flOosmIqiTixJvjHfljl19uxvU3bG7u1BqLNPujaRok5K56PGkoe3VJGg18JkfCrHzHhBQe9EUawt5CuHUbgrpYEOBMBfNzllO5LCg5slYvV4zTRoxsN7G18vuXxxx1UbwtelduR3zRoBN3StEgbJdCwYJuZiI4e"
      # AZURE_TENANT_ID       = "223ac286-feec-4e97-b3d8-d228c0946086"
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


# module "key_vault" {
#   source  = "aztfmod/caf-keyvault/azurerm"
#   version = "~> 2.0.0"

#   prefix                  = var.prefix
#   location                = azurerm_resource_group.rg.location
#   resource_group_name     = azurerm_resource_group.rg.name
#   akv_config              = local.akv_config
#   tags                    = var.tags
#   diagnostics_settings    = local.diagnostics_settings
#   diagnostics_map         = local.diagnostics_map
#   log_analytics_workspace = local.log_analytics_workspace
#   convention              = var.convention
# }

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

# TODO: test in DEV only, to be removed
resource "azurerm_key_vault_access_policy" "rovergroupid" {

  key_vault_id = azurerm_key_vault.akv.id
  tenant_id    = local.tenant_id
  object_id    = "68a4dfcb-03e8-443e-8213-6211555f8fc5"

  key_permissions = []

  certificate_permissions = [
    "Get",
    "List",
    "Create",
    "Delete",
    "Import",
  ]
  # backup, create, delete, deleteissuers, get, getissuers, import, 
  # list, listissuers, managecontacts, manageissuers, purge, recover, restore, setissuers and update.
}



# provider "acme" {
#   server_url = "https://acme-v02.api.letsencrypt.org/directory"
# }

# resource "tls_private_key" "private_key" {
#   algorithm = "RSA"
# }

# resource "acme_registration" "reg" {
#   account_key_pem = tls_private_key.private_key.private_key_pem
#   email_address   = "hieunhu@microsoft.com"
# }

# resource "acme_certificate" "certificate" {
#   account_key_pem          = acme_registration.reg.account_key_pem
#   common_name              = "*.petcafsandpit789.com"
#   certificate_p12_password = "testpassword"

#   dns_challenge {
#     provider = "azure"
#     config = {
#       # AZURE_SUBSCRIPTION_ID = "0d942dd6-0ff2-4601-a9da-0ae82683948b"
#       # AZURE_CLIENT_ID       = "b68e0201-da17-4150-84a1-18b6b8b1855f"
#       # AZURE_CLIENT_SECRET   = "G4lpCyzTS2201xqatpYAbajVUAX5NPPTJmfjgj52dgLk6POHJSMMny5xtZNjCdA3coZfNsswy57O7z37n3AbThgRd7flOosmIqiTixJvjHfljl19uxvU3bG7u1BqLNPujaRok5K56PGkoe3VJGg18JkfCrHzHhBQe9EUawt5CuHUbgrpYEOBMBfNzllO5LCg5slYvV4zTRoxsN7G18vuXxxx1UbwtelduR3zRoBN3StEgbJdCwYJuZiI4e"
#       # AZURE_TENANT_ID       = "223ac286-feec-4e97-b3d8-d228c0946086"
#       AZURE_RESOURCE_GROUP  = "oqny-domain"
#     }
#   }
# }
