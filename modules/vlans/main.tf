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
  raw_yaml = yamldecode(file("${path.root}/common.yaml"))

  # Filter in the 'common_settings' block 
  # so Terraform uses only the common settings (vlans)

  device_data = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

# 2. Flatten: Create a map entry for every VLAN on every device
  device_vlans = merge([
    for device_key, device_val in local.device_data: {
      for vlan_id, vlan_val in local.raw_yaml.common_settings.vlans :
      "${device_key}.${vlan_id}" => {
        device       = device_key
        vlan_id      = try(vlan_id, "enabled") # This is a workaround to handle the case where vlan_id might not be present in the YAML")
        name         = try(vlan_val.name, "DEFAULT")
        fabric_encap = try(vlan_val.fabric_encap, 999)
        #bfd_admin_state = try(local.raw_yaml.common_settings.features.bfd.admin_state, "disabled")
      }
    }
  ]...) # The '...' is important to merge the list of maps into one map

  
}

provider "nxos" {
  username = "cisco"
  password = "cisco"
  devices  = concat(local.leafs)
}

##### VRF Config

##### Add the vlan using the provider. Note I do not see how to add a vlan name?
##### Adding each vlan seperatley as unsure how to loop through the map of vlan in the vlans.yaml file. This is a workaround to get the VRF created and then we can add the interfaces to it in the Eth_Int module.

resource "nxos_bridge_domain" "bd-vlan3010" {
  for_each = local.device_data
  device = each.key 
  #svi_autostate = "disable"
  bridge_domains = {
    "vlan-3010" = {
      #access_encap        = "unknown"
      name                = "vlan-3010"
      #bridge_domain_state = "suspend"
      #admin_state         = "active"
      #bridge_mode         = "mac"
      #control             = "untagged"
      #forwarding_control  = "mdst-flood"
      #forwarding_mode     = "bridge"
      #long_name           = false
      #mac_packet_classify = "enable"
      #mode                = "CE"
      #vrf_name            = "default"
      #cross_connect       = "disable"
    }
    "vlan-3020" = {
      name                = "vlan-3020"
    }
    "vlan-3030" = {
      name                = "vlan-3030"
    }
    "vlan-3060" = {
      name                = "vlan-3060"
    }
  

  }
}



##### OUTPUT Module - will be used to return output to Root #####