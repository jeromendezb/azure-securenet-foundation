terraform {
  required_version = ">= 1.16, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  # Remote state in Azure Storage (ADR-005). The storage account is created by
  # scripts/bootstrap-state.ps1, not by Terraform.
  backend "azurerm" {
    resource_group_name  = "rg-securenet-tfstate-dev-eus-001"
    storage_account_name = "stsecurenettfstate001"
    container_name       = "tfstate"
    key                  = "governance.tfstate"
    use_azuread_auth     = true
  }

}

provider "azurerm" {
  features {}
}
