resource "azurerm_resource_group" "grupo_lab1" {
    name = var.resource_group_name
    location = var.location
}

resource "azurerm_virtual_network" "red_virtual"{
    name = var.virtual_network_name
    address_space = [var.vnet_address_space]
    location = var.location
    resource_group_name = azurerm_resource_group.grupo_lab1.name
}

resource "azurerm_subnet" "subnet1"{
    name = var.subnet_name1
    resource_group_name = azurerm_resource_group.grupo_lab1.name
    virtual_network_name = var.virtual_network_name
    address_prefixes = [var.subnet1_prefix]
}

resource "azurerm_subnet" "subnet2"{
    name = var.subnet_name2
    resource_group_name = azurerm_resource_group.grupo_lab1.name
    virtual_network_name = var.virtual_network_name
    address_prefixes = [var.subnet2_prefix]
}