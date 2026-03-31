# Configure the required provider for Cisco NX-OS
terraform {
  required_providers {
    nxos = {
      source  = "CiscoDevNet/nxos"
      version = ">= 0.8.0"
    }
  }
}

locals {
  # 1. Load and parse the YAML file from the root/modules/yaml_configs/ directory

  raw_yaml = yamldecode(file(("${path.module}/../yaml_configs/system.yaml")))
  
  # 2. Filter out the "common_settings" metadata block.
  # This creates a map of actual switches only, preventing Terraform 
  # from trying to configure a "switch" named "common_settings".
  device_list = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

  # 3. Flattening Logic:
  # Since 'for_each' can only loop over a single-level map, we must 
  # transform the nested structure (Switch -> Features) into a flat map.
  device_features = {
    for device_key, device_val in local.device_list : device_key => {
      device_name    = device_key
      # Use try() to look into the features map, defaulting to "disabled"
      bgp            = try(device_val.features.bgp, "disabled")
      bfd            = try(device_val.features.bfd, "disabled")
      hsrp           = try(device_val.features.hsrp, "disabled")
      interface_vlan = try(device_val.features.interface_vlan, "disabled")
      lacp           = try(device_val.features.lacp, "disabled")
      lldp           = try(device_val.features.lldp, "disabled")
      macsec         = try(device_val.features.macsec, "disabled")
      tacacs         = try(device_val.features.tacacs, "disabled")
      vpc            = try(device_val.features.vpc, "disabled")

    }
  }
  
  #3. Flattening Logic:
  # Since 'for_each' can only loop over a single-level map, we must 
  # transform the nested structure (Switch -> ntp) into a flat map.
  device_ntp = merge([
    for device_key, device_val in local.device_list : {
    # Iterate over the 'ntp' map inherited by each switch via the YAML alias (*)    
      for ntp_id, ntp_val in device_val.ntp :
      # Generate a unique key for every port on every switch (e.g., "twe-agg01.130")
      "${device_key}.${ntp_id}" => {
        device_name  = device_key
        ntp_id      = ntp_id
        vrf         = ntp_val.vrf
        #prefered    = ntp_val.prefered
      }
    }
  ]...) # The '...' expansion operator merges the list of maps into one single map

}
 
provider "nxos" {
  username = "cisco" # these should be moved to a secure method
  password = "cisco" # these should be moved to a secure method

  # List of target devices. The 'name' here must match the 'device' 
  # attribute used in the resources below.
  devices = [
    { name = "twe-agg01", url = "https://192.168.1.87" },
    { name = "twe-agg02", url = "https://192.168.1.190" }
  ]
}

##### nxos_feature #####
# Dynamic resource creation for switch features
resource "nxos_feature" "dynamic_features" {
  # This now loops twice (once per switch)
  for_each = local.device_features

  # Directs the configuration to the specific switch (e.g., "twe-agg01")
  device = each.value.device_name

  # Define the Features setting
  bgp            = "${each.value.bgp}"
  bfd            = "${each.value.bfd}"
  hsrp           = "${each.value.hsrp}"
  interface_vlan = "${each.value.interface_vlan}"
  lacp           = "${each.value.lacp}"
  lldp           = "${each.value.lldp}"
  macsec         = "${each.value.macsec}"
  tacacs         = "${each.value.tacacs}"
  vpc            = "${each.value.vpc}"
  } 

##### NTP #####
# Dynamic resource creation for switch ntp
resource "nxos_ntp" "example" {
  for_each = local.device_ntp
  device = each.value.device_name
  servers = {
    "${each.value.ntp_id}" = {
      vrf       = "management"
      type      = "server"
    }
  # "4.3.2.1" = {
  #   vrf       = "management"
  #   type      = "server"
  #   }
  }
}

##### TLDR #####
#
# What this code achieves:
#
# Scalability: If you add a new feature to the #common_settings# in your YAML, 
#    Terraform will automatically create it on both switches.
#
# Traceability: Every resource is indexed in your state file by a readable 
#    name like dynamic_vlans["twe-agg01.130"].
#
# Separation of Concerns: The provider handles the connection, 
#    the locals handle the data transformation, and the resource handles the intent.