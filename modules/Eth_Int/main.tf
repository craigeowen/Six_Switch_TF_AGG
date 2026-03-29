# terraform {
#   required_providers {
#     nxos = {
#       source  = "CiscoDevNet/nxos"
#       version = ">= 0.8.0" # example, pin what you actually use
#     }
#   }
# }

# locals {
#   leafs = [
#     {
#       name = "twe-sat01"
#       url  = "https://192.168.1.166"

#     },
#     {
#       name = "twe-sat02"
#       url  = "https://192.168.1.144"

#     },
#   ]
#   raw_yaml = yamldecode(file("${path.root}/Eth_Int.yaml"))

#   # Filter in the 'common_settings' block 
#   # so Terraform uses only the common settings (vlans)

#   device_data = { 
#     for k, v in local.raw_yaml : k => v 
#     if k != "common_settings" 
#   }

# # 2. Flatten: Create a map entry for every VLAN on every device
#   # device_config = merge([
#   #   for device_key, device_val in local.device_data: {
#   #     for dev_id, dev_val in local.raw_yaml.common_settings.l2_eth_interface :
#   #     "${device_key}.${dev_id}" => {
#   #       device       = device_key
#   #       dev_id        = dev_id
#   #       interface_id = try(dev_val.interface_id, null)
#   #       admin_state  = try(dev_val.admin_state, "down")
#   #       mode         = try(dev_val.mode, null)
#   #       trunk_vlans  = try(dev_val.trunk_vlans, null)
#   #       description  = try(dev_val.description, "SHUTDOWN")
#   #       layer        = try(dev_val.layer, "Layer2")
#   #       #mtu          = try(dev_val.mtu, null)  
#   #       # interface_id = dev_val.interface_id
#   #       # admin_state  = dev_val.admin_state
#   #       # mode         = dev_val.mode
#   #       # trunk_vlans  = dev_val.trunk_vlans
#   #       # description  = dev_val.description
#   #       # layer        = dev_val.layer
#   #       #mtu          = dev_val.mtu
#   #     }
#   #   }
#   # ]...) # The '...' is important to merge the list of maps into one map


# # 3. Flatten and apply safety nets
#   device_config = {
#     for item in flatten([
#       for device_key, device_val in local.device_data : [
#         # We loop through the interfaces ALREADY MERGED into the device
#         for int_id, int_val in lookup(device_val, "l2_eth_interface", {}) : {
          
#           unique_key   = "${device_key}.${int_id}"
#           device       = device_key
          
#           # Use try() to provide defaults for optional fields
#           interface_id = int_val.interface_id
#           admin_state  = try(int_val.admin_state, "up")
#           mode         = try(int_val.mode, "trunk")
#           trunk_vlans  = try(int_val.trunk_vlans, "1")
#           description  = try(int_val.description, "Managed by Terraform")
#           layer        = try(int_val.layer, "Layer2")
          
#           # Example for MTU which might be commented out in YAML
#           mtu          = try(int_val.mtu, 1500) 
#         }
#       ]
#     ]) : item.unique_key => item
#   }

# }

# provider "nxos" {
#   username = "cisco"
#   password = "cisco"
#   devices  = concat(local.leafs)
# }

# ##### Layer 2 Eth Int #####

# resource "nxos_physical_interface" "l2_eth_interface" {
#   for_each              = {for k, v in local.device_config : k => v}
#   interface_id          = "${each.value.interface_id}"
#   admin_state           = lookup(each.value, "admin_state", null)
#   mode                  = lookup(each.value, "mode", null)
#   trunk_vlans           = lookup(each.value, "trunk_vlans", null)
#   description           = lookup(each.value, "description", null)
#   layer                 = lookup(each.value, "layer", null)
#   mtu                   = lookup(each.value, "mtu", null)
# }


# ##### OUTPUT Module - will be used to return output to Root #####
# data "nxos_physical_interface" "l2_eth_interface" {
#   for_each = local.device_config
#   device = each.value.device
#   interface_id          = "${each.value.interface_id}"
# }

# output "l2_eth_interface" {
#   value = data.nxos_physical_interface.l2_eth_interface
# }

