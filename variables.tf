variable "workload" {
  description = "Nombre del workload/proyecto, usado en la convencion de nombres"
  type        = string
  default     = "securenet"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "dev"
}

variable "location" {
  description = "Region de azure"
  type        = string
  default     = "eastus"
}

variable "location_short" {
  description = "Abreviatura de la region"
  type        = string
  default     = "eus"
}

variable "vnet_address_space" {
  description = "Rango CIDR de la Vnet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "snet_app_prefix" {
  description = "Rango CIDR de la subnet de aplicacion"
  type        = string
  default     = "10.0.1.0/24"
}

variable "snet_mgmt_prefix" {
  description = "Rango CIDR de la subnet de gestion"
  type        = string
  default     = "10.0.2.0/24"
}

locals {
  name_suffix = "${var.workload}-${var.environment}-${var.location_short}-001"

  common_tags = {
    project     = var.workload
    environment = var.environment
    owner       = "jeromendezb"
    managed_by  = "terraform"
  }
}
