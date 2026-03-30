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
  raw_yaml = yamldecode(file("${path.root}/Eth_Int.yaml"))

  # Filter in the 'common_settings' block 
  # so Terraform uses only the common settings (vlans)

  device_data = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

  loopback_octet = "10.66.127"
  xx01-xx-core_octet = "10.66.125"
  prod_xx_octet = "10.66.32"

# 2. Flatten: Create a map entry for every VLAN on every device
  # device_config = merge([
  #   for device_key, device_val in local.device_data: {
  #     for dev_id, dev_val in local.raw_yaml.common_settings.l2_eth_interface :
  #     "${device_key}.${dev_id}" => {
  #       device       = device_key
  #       dev_id        = dev_id
  #       interface_id = try(dev_val.interface_id, null)
  #       admin_state  = try(dev_val.admin_state, "down")
  #       mode         = try(dev_val.mode, null)
  #       trunk_vlans  = try(dev_val.trunk_vlans, null)
  #       description  = try(dev_val.description, "SHUTDOWN")
  #       layer        = try(dev_val.layer, "Layer2")
  #       #mtu          = try(dev_val.mtu, null)  
  #       # interface_id = dev_val.interface_id
  #       # admin_state  = dev_val.admin_state
  #       # mode         = dev_val.mode
  #       # trunk_vlans  = dev_val.trunk_vlans
  #       # description  = dev_val.description
  #       # layer        = dev_val.layer
  #       #mtu          = dev_val.mtu
  #     }
  #   }
  # ]...) # The '...' is important to merge the list of maps into one map


# 3. Flatten and apply safety nets
  device_config = {
    for item in flatten([
      for device_key, device_val in local.device_data : [
        # We loop through the interfaces ALREADY MERGED into the device
        for int_id, int_val in lookup(device_val, "l2_eth_interface", {}) : {
          
          unique_key   = "${device_key}.${int_id}"
          device       = device_key
          
          # Use try() to provide defaults for optional fields
          interface_id = int_val.interface_id
          admin_state  = try(int_val.admin_state, "up")
          mode         = try(int_val.mode, "trunk")
          trunk_vlans  = try(int_val.trunk_vlans, "1")
          description  = try(int_val.description, "Managed by Terraform")
          layer        = try(int_val.layer, "Layer2")
          
          # Example for MTU which might be commented out in YAML
          mtu          = try(int_val.mtu, 1500) 
        }
      ]
    ]) : item.unique_key => item
  }

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