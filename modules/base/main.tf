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
  # 1. Load and parse the YAML file from the root directory
  raw_yaml = yamldecode(file("${path.root}/base.yaml"))

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