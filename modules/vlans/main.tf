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
  # Load and parse the YAML file from the root directory
  raw_yaml = yamldecode(file("${path.root}/vlans.yaml"))

  # 1. Filter out the "common_settings" metadata block.
  # This creates a map of actual switches only, preventing Terraform 
  # from trying to configure a "switch" named "common_settings".
  device_list = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

  # 2. Flattening Logic:
  # Since 'for_each' can only loop over a single-level map, we must 
  # transform the nested structure (Switch -> VLANs) into a flat map.
  device_vlans = merge([
    for device_key, device_val in local.device_list : {
    # Iterate over the 'vlans' map inherited by each switch via the YAML alias (*)    
      for vlan_id, vlan_val in device_val.vlans :
      # Generate a unique key for every port on every switch (e.g., "twe-agg01.130")
      "${device_key}.${vlan_id}" => {
        device_name  = device_key
        vlan_id      = vlan_id
        vlan_name    = vlan_val.name
        fabric_encap = vlan_val.fabric_encap
      }
    }
  ]...) # The '...' expansion operator merges the list of maps into one single map
}

provider "nxos" {
  username = "cisco"
  password = "cisco"

  # List of target devices. The 'name' here must match the 'device' 
  # attribute used in the resources below.
  devices = [
    { name = "twe-agg01", url = "https://192.168.1.87" },
    { name = "twe-agg02", url = "https://192.168.1.190" }
  ]
}

# Dynamic resource creation for Bridge Domains (VLANs)
resource "nxos_bridge_domain" "dynamic_vlans" {
  # Create one Bridge Domain for every entry in our flattened 'device_vlans' map
  for_each = local.device_vlans

  # Directs the configuration to the specific switch (e.g., "twe-agg01")
  device = each.value.device_name

  # Define the Bridge Domain setting
  bridge_domains = {
    "vlan-${each.value.vlan_id}" = {
      name = each.value.vlan_name
    }
  }
}

##### TLDR #####
#
# What this code achieves:
#
# Scalability: If you add a new VLAN to the common_settings in your YAML, 
#    Terraform will automatically create it on both switches.
#
# Traceability: Every resource is indexed in your state file by a readable 
#    name like dynamic_vlans["twe-agg01.130"].
#
# Separation of Concerns: The provider handles the connection, 
#    the locals handle the data transformation, and the resource handles the intent.