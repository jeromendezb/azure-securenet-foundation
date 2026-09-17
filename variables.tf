variable "location" {
  description = "Región de Azure donde se despliegan los recursos"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Nombre del resource group"
  type        = string
  default     = "rg-terraform-lab1"
}

variable "virtual_network_name"{
    description= "nombre de la vnet"
    type = string 
    default = "vnet_terraform_lab1"
}

variable "subnet_name1"{
    description = "nombre de la subnet1"
    type = string 
    default = "subnet1_terraform_lab1"
}

variable "subnet_name2"{
    description = "nombre de la subnet2"
    type = string 
    default = "subnet2_terraform_lab1"
}

variable "vnet_address_space" {
  description = "Rango de direcciones de la VNet"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet1_prefix" {
  description = "Rango de direcciones de la subnet 1"
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet2_prefix" {
  description = "Rango de direcciones de la subnet 2"
  type        = string
  default     = "10.0.2.0/24"
}