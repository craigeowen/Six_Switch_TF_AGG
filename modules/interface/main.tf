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

    },
    {
      name = "twe-agg02"
      url  = "https://192.168.1.190"

    },
    
  ]
  raw_yaml = yamldecode(file(("${path.module}/../yaml_configs/interface.yaml")))

  #1.  Filter in the 'common_settings' block 
  # so Terraform uses only the common settings (vlans)

  device_data = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

  # 2. Loopback Interfces 
  #Flattening Logic:
  # Since 'for_each' can only loop over a single-level map, we must 
  # transform the nested structure (Switch -> loopback_interfaces) into a flat map.
  device_lo_int = merge([
    for device_key, device_val in local.device_data : {
    # Iterate over the 'vlans' map inherited by each switch via the YAML alias (*)    
      for lo_int_id, lo_int_val in device_val.loopback_interfaces :
      # Generate a unique key for every port on every switch (e.g., "twe-agg01.130")
      "${device_key}.${lo_int_id}" => {
        device_name  = device_key
        lo_int_id    = lo_int_id
        admin_state  = lo_int_val.admin_state
        description  = lo_int_val.description
        vrf_dn       = lo_int_val.vrf_dn
      }
    }
  ]...) # The '...' expansion operator merges the list of maps into one single map
}






provider "nxos" {
  username = "cisco"
  password = "cisco"
  devices  = concat(local.leafs)
}

provider "nxos" {
  alias = "twe-agg01"
  username = "cisco"
  password = "cisco"
  url      = "https://192.168.1.87"
}
provider "nxos" {
  alias = "twe-agg02"
  username = "cisco"
  password = "cisco"
  url      = "https://192.168.1.190"
}


##### lOOPBACK Interfaces #####
resource "nxos_loopback_interface" "example" {
    # Create one Bridge Domain for every entry in our flattened 'device_vlans' map
  for_each = local.device_lo_int

  # Directs the configuration to the specific switch (e.g., "twe-agg01")
  device = each.value.device_name
  loopback_interfaces = {
    "${each.value.lo_int_id}" = {
      admin_state  = each.value.admin_state
      description  = each.value.description
      vrf_dn       = each.value.vrf_dn
    }
  }
}
