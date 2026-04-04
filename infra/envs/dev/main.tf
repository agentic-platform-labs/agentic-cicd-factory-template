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
  features {}
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------
locals {
  tags = merge(var.tags, {
    environment = var.environment
    project     = var.project
    managed-by  = "terraform"
    source-repo = "agentic-cicd-factory-template"
  })
}

# ---------------------------------------------------------------------------
# Resources — scaffolded via @terraform-module-expert Copilot agent
# ---------------------------------------------------------------------------
