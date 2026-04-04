terraform {
  required_version = ">= 1.7"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {
    # Injected at runtime via -backend-config flags in CI.
    # See docs/ONBOARDING.md for the bootstrap scripts that create this backend.
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.project}-${var.environment}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Storage Account — Static Website Hosting
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "web" {
  name                     = lower(substr(replace("st${var.project}${var.environment}web", "/[^a-z0-9]/", ""), 0, 24))
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  https_traffic_only_enabled = true

  static_website {
    index_document     = "index.html"
    error_404_document = "404.html"
  }

  tags = local.tags
}

# Upload a minimal demo index.html so the static website actually works
resource "azurerm_storage_blob" "index" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  source_content = <<HTML
<!DOCTYPE html>
<html>
<head><title>Agentic CI/CD Factory Template</title></head>
<body>
  <h1>🚀 Agentic CI/CD Factory Template</h1>
  <p>Deployed to: <strong>${var.environment}</strong></p>
  <p>This static site was deployed by GitHub Actions using OIDC + Terraform.</p>
  <p>See <a href="https://github.com/Dhineshkumarganesan/agentic-cicd-factory-template">the template repo</a> to learn how.</p>
</body>
</html>
HTML
}

resource "azurerm_storage_blob" "error" {
  name                   = "404.html"
  storage_account_name   = azurerm_storage_account.web.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"
  source_content         = "<!DOCTYPE html><html><body><h1>404 - Page Not Found</h1></body></html>"
}

# ---------------------------------------------------------------------------
# Key Vault — RBAC-enabled, no secrets created
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "kv" {
  name                        = lower(substr(replace("kv-${var.project}-${var.environment}", "/[^a-z0-9-]/", ""), 0, 24))
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization   = true   # RBAC mode — no access policies
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false  # allow cleanup in lab; enable in prod

  network_acls {
    default_action = "Allow"   # open for demo; restrict in prod
    bypass         = "AzureServices"
  }

  tags = local.tags
}

# Grant the CI/CD service principal Key Vault Secrets Officer so it can
# manage secrets in future without needing access policy changes.
resource "azurerm_role_assignment" "kv_sp" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

locals {
  tags = merge(var.tags, {
    environment = var.environment
    project     = var.project
    managed-by  = "terraform"
    source-repo = "agentic-cicd-factory-template"
  })
}
