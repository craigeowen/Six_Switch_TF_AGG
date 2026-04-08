terraform {
  required_providers {
    nxos = {
      source  = "CiscoDevNet/nxos"
      version = ">= 0.8.0" # example, pin what you actually use
    }
  }
}

locals {
  leafs = [
    {
      name = "twe-agg01"
      url  = "https://192.168.1.87"
      number = 1
      alias = "twe-agg01"
    },
    {
      name = "twe-agg02"
      url  = "https://192.168.1.190"
      number = 2
      alias = "twe-agg02"
    },
    
  ]
  raw_yaml = yamldecode(file("./base.yaml"))

  # Filter out the 'common_settings' block so Terraform doesn't 
  # try to treat it like a real switch.
  device_data = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

# 1. Extract the common settings into a single object
  common = local.raw_yaml["common_settings"]

  common_data = { 
    for k, v in local.raw_yaml : k => v 
    if k == "common_settings" 
  }

#

  # # 3. Flatten: Create a map entry for every VRF on every device
  # device_vrfs = merge([
  #   for device_key, device_val in local.device_data: {
  #     for vrf_id, vrf_val in local.raw_yaml.common_settings.vrfs :
  #     "${device_key}.${vrf_id}" => {
  #       device       = device_key
  #       name         = vrf_val.name
  #       description  = vrf_val.description
  #     }
  #   }
  # ]...) # The '...' is important to merge the list of maps into one map

###### Extract the commn.yaml data into a separate local variable for easier reference in the module
  #raw_vlans_yaml = yamldecode(file("./vlans.yaml")) 

}

# Parses a YAML file into a Terraform-compatible map or object structure.
  # 'file' reads the raw text from the disk.
  # 'yamldecode' converts that text into data (lists, maps, strings).
# locals {
#   device_data = yamldecode(file("./base.yaml"))
# }



provider "nxos" {
  username = "cisco"
  password = "cisco"
  devices  = concat(local.leafs)
}

# Configures the system-level hostname for NX-OS devices
resource "nxos_system" "hostname" {
  for_each = local.device_data
  # Iterates over a collection of devices defined in local.cfg.devices
  # This allows you to manage multiple switches from a single resource block
  device = each.key
  name   = "XX-SPR-2B-${each.value.name}"
  # Sets the hostname ('name') based on the 'name' attribute of the current device in the loop
}
##### Each block is composed of
##### A Resource Block
##### A data block
##### An output block whcih hold the output


##### This is usewd for returned OUTPUT from Modules #####


##### SAVE RUNNING CONFIG TO STARTUP CONFIG #####

resource "nxos_save_config" "save-config" {
  for_each = local.device_data
  device = each.key
}




##### Configure  modules #####

### Base
# module "config-base" {
#   source = "./modules/base"
#   #device_features = local.device_features
#   #device_vrfs = local.device_vrfs
# }

### Vlans
#module "config-common-vlans" {
#  source = "./modules/vlans"
#  #common_vlan = local.device_vlans
#}

# ### Eth Int
# module "config-Eth-Ints" {
#   source = "./modules/Eth_Int"
# }

### VPC
#module "config-VPC" {
#  source = "./modules/vpc"
#}

 ### Eth Int
 module "config-interfaces" {
   source = "./modules/interfaces"
 }

 ### IPV4
 module "config-ipv4-addresses" {
   source = "./modules/ipv4address"
 }

### BGP
module "config-BGP" {
  source = "./modules/routing"
}

### interface
 module "config-interface" {
   source = "./modules/interface"
 }

### Switching
module "config-Switching" {
  source = "./modules/switching"
}


### system
module "config-system" {
  source = "./modules/system"
  # Read the file here, where the path is simple and clear
  #system_config = yamldecode(file("${path.root}/modules/yaml_configs/system.yaml"))
}

####################################################

