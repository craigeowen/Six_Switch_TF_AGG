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

  # 3. Flatten: Create a map entry for every VRF on every device
  device_vrfs = merge([
    for device_key, device_val in local.device_data: {
      for vrf_id, vrf_val in local.raw_yaml.common_settings.vrfs :
      "${device_key}.${vrf_id}" => {
        device       = device_key
        name         = vrf_val.name
        description  = vrf_val.description
      }
    }
  ]...) # The '...' is important to merge the list of maps into one map

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

##### VRF Config

##### Add the vrf using the rest apiu as provider method does not work!
##### Adding each vrf seperatley as unsure how to loop through the map of vrfs in the common.yaml file. This is a workaround to get the VRF created and then we can add the interfaces to it in the Eth_Int module.
resource "nxos_dme" "l3Inst-xx01" {
  for_each = local.device_data
  device = each.key  
  dn         = "sys/inst-[xx01-xx-core]"
  class_name = "l3Inst"
  content = {
    name  = "xx01-xx-core"
    descr = "VRF for xx01-xx-core"
  }
}
resource "nxos_dme" "l3Inst-xx02" {
  for_each = local.device_data
  device = each.key  
  dn         = "sys/inst-[xx02-xx-core]"
  class_name = "l3Inst"
  content = {
    name  = "xx02-xx-core"
    descr = "VRF for xx02-xx-core"
  }
}
resource "nxos_dme" "l3Inst-xx03" {
  for_each = local.device_data
  device = each.key  
  dn         = "sys/inst-[xx03-xx-core]"
  class_name = "l3Inst"
  content = {
    name  = "xx03-xx-core"
    descr = "VRF for xx03-xx-core"
  }
}
resource "nxos_dme" "l3Inst-xx06" {
  for_each = local.device_data
  device = each.key  
  dn         = "sys/inst-[xx06-xx-core]"
  class_name = "l3Inst"
  content = {
    name  = "xx06-xx-core"
    descr = "VRF for xx06-xx-core"
  }
}
resource "nxos_dme" "l3Inst-vpc" {
  for_each = local.device_data
  device = each.key  
  dn         = "sys/inst-[vpc]"
  class_name = "l3Inst"
  content = {
    name  = "vpc"
    descr = "VRF for vpc"
  }
}


##### End of VRF Config


##### This is usewd for returned OUTPUT from Modules #####


##### SAVE RUNNING CONFIG TO STARTUP CONFIG #####

resource "nxos_save_config" "save-config" {
  for_each = local.device_data
  device = each.key
}




##### Configure  modules #####

### Base
module "config-base" {
  source = "./modules/base"
  #device_features = local.device_features
  #device_vrfs = local.device_vrfs
}

### Vlans
module "config-common-vlans" {
  source = "./modules/vlans"
  #common_vlan = local.device_vlans
}

# ### Eth Int
# module "config-Eth-Ints" {
#   source = "./modules/Eth_Int"
# }

### VPC
module "config-VPC" {
  source = "./modules/vpc"
}

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

####################################################

