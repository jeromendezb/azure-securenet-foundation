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

variable "snet_bastion_prefix" {
  description = "Rango CIDR de AzureBastionSubnet (minimo /26 por requisito de azure)"
  type        = string
  default     = "10.0.3.0/26"
}

variable "vm_size" {
  description = "Tamaño de la VM de aplicación"
  type        = string
  default     = "Standard_F1als_v7"
}

variable "admin_username" {
  description = "Usuario administrador de la VM"
  type        = string
  default     = "azureadmin"
}

variable "ssh_public_key_path" {
  description = "Ruta al archivo de clave publica SSH"
  type        = string
  default     = "~/.ssh/securenet_lab.pub"
}