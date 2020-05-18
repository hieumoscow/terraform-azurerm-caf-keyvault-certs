provider "azurerm" {
  version = "<= 2.2.0"
  features {
    key_vault {
      recover_soft_deleted_key_vaults = false
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

data "azurerm_client_config" "current" {}


locals {
  module_tag = {
    "module" = basename(abspath(path.module))
  }
  tags             = merge(var.tags, local.module_tag)
  
  tenant_id               = data.azurerm_client_config.current.tenant_id
  object_id               = data.azurerm_client_config.current.object_id

}
