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

  raw_yaml = yamldecode(file(("${path.module}/../yaml_configs/routing.yaml")))

  # Filter in the 'common_settings' block 
  # so Terraform uses only the common settings (vlans)

  device_data = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

  loopback_octet = "10.66.127"
  xx01-xx-core_octet = "10.66.125"
  prod_xx_octet = "10.66.32"




  #1. VRF
  #Flattening Logic:
  # Since 'for_each' can only loop over a single-level map, we must 
  # transform the nested structure (Switch -> vrfs) into a flat map.
  device_vrf = merge([
    for device_key, device_val in local.device_data : {
    # Iterate over the 'vrfs' map inherited by each switch via the YAML alias (*)    
      for vrf_id, vrf_val in device_val.vrfs :
      # Generate a unique key for every port on every switch (e.g., "twe-agg01.130")
      "${device_key}.${vrf_id}" => {
        device_name  = device_key
        vrf_id      = vrf_id
        description         = vrf_val.description
        
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

### VRF Creation

resource "nxos_vrf" "example" {
  for_each = local.device_vrf
  device = each.value.device_name
  vrfs = {
    "${each.value.vrf_id}" = {
      description         = each.value.description
    
    }
  }
}


##### BGP configuration #####

resource "nxos_bgp" "bgp-agg01" {
  provider = nxos.twe-agg01
  admin_state                              = "enabled"
  instance_admin_state                     = "enabled"
  asn                                      = "65292"
  
  vrfs = {
    "default" = {
      peer_templates = {
        "ibgp-baseline" = {
          remote_asn                     = "65292"
          description                    = "IBGP BASAELINE TEMPLATE"
          hold_time                      = 30
          keepalive_interval             = 10
          peer_template_address_families = {
            "ipv4-ucast" = {
              control                       = "nh-self,rr-client"
              send_community_extended       = "enabled"
              send_community_standard       = "enabled"
              soft_reconfiguration_backup   = "inbound"
            }
          }
        }
      }
    }
    #
    "xx01-xx-core" = {
      router_id                          = "10.66.127.3"

      address_families = {
        "ipv4-ucast" = {

          advertised_prefixes = {
            "10.66.127.3/32" = {

            }
          }
 
        }
      }
      
      
      peers = {
        "10.66.127.4" = {
          description                    = "TF-BGP-TO-AGG02"
          peer_template                  = "ibgp-baseline"
          source_interface               = "lo101"
          # password_type                  = "LINE"
          # password                       = "secret_password"
          admin_state                    = "enabled"

        }
      }
    }
  }
}

resource "nxos_bgp" "bgp-agg02" {
  provider = nxos.twe-agg02
  admin_state                              = "enabled"
  instance_admin_state                     = "enabled"
  asn                                      = "65292"
  
  vrfs = {
    "default" = {
      peer_templates = {
        "ibgp-baseline" = {
          remote_asn                     = "65292"
          description                    = "IBGP BASAELINE TEMPLATE"
          hold_time                      = 30
          keepalive_interval             = 10
          peer_template_address_families = {
            "ipv4-ucast" = {
              control                       = "nh-self,rr-client"
              send_community_extended       = "enabled"
              send_community_standard       = "enabled"
              soft_reconfiguration_backup   = "inbound"
            }
          }
        }
      }
    }
    #
    "xx01-xx-core" = {
      router_id                          = "10.66.127.4"

      address_families = {
        "ipv4-ucast" = {

          advertised_prefixes = {
            "10.66.127.4/32" = {

            }
          }
 
        }
      }
      
      
      peers = {
        "10.66.127.3" = {
          description                    = "TF-BGP-TO-AGG02"
          peer_template                  = "ibgp-baseline"
          source_interface               = "lo101"
          # password_type                  = "LINE"
          # password                       = "secret_password"
          admin_state                    = "enabled"

        }
      }
    }
  }
}