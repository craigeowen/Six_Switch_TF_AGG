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
      name = "twe-sat01"
      url  = "https://192.168.1.166"

    },
    {
      name = "twe-sat02"
      url  = "https://192.168.1.144"

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
  alias = "twe-sat01"
  username = "cisco"
  password = "cisco"
  url      = "https://192.168.1.166"
}
provider "nxos" {
  alias = "twe-sat02"
  username = "cisco"
  password = "cisco"
  url      = "https://192.168.1.144"

}

##### IPV4 Interface Addresses #####

resource "nxos_ipv4" "sat01" {
  provider = nxos.twe-sat01  
  # admin_state                             = "enabled"
  # instance_admin_state                    = "enabled"
  # access_list_match_local                 = "enabled"
  vrfs = {
     "vpc" = {

      interfaces = {
        "po4" = {

          addresses = {
            "1.1.1.1/30" = {

            }
          }
        }
      }
    }
  "xx01-xx-core" = {
    #   auto_discard                 = "enabled"
    #   icmp_errors_source_interface = "unspecified"
       static_routes = {
         "${local.loopback_octet}.6/32" = {
    #       control     = "bfd"
           description = "SR_TO_SAT02_LOOPBACK"
    #       preference  = 2
    #       tag         = 10
           next_hops = {
             "po2.3010;${local.xx01-xx-core_octet}.21;xx01-xx-core" = {
    #           description           = "My Description"
    #           object                = 10
    #           preference            = 123
    #           tag                   = 10
    #           name                  = "nh1"
    #           rewrite_encapsulation = "unknown"
             }
           }
         }
       }
      interfaces = {
        "lo101" = {

          addresses = {
            "${local.loopback_octet}.5/32" = {

            }
          }
        }
        "po2.3010" = {

          addresses = {
            "${local.xx01-xx-core_octet}.20/31" = {

            }
          }
        }
        "po11.3010" = {

          addresses = {
            "${local.xx01-xx-core_octet}.13/31" = {

            }
          }
        }
        "po21.3010" = {

          addresses = {
            "${local.xx01-xx-core_octet}.17/31" = {

            }
          }
        }
        "vlan650" = {

          addresses = {
            "${local.prod_xx_octet}.30/27" = {

            }
          }
        }
        "vlan651" = {

          addresses = {
            "${local.prod_xx_octet}.62/27" = {

            }
          }  
        }
      }
    }
  }
}



resource "nxos_ipv4" "sat02" {
  provider = nxos.twe-sat02 
  # admin_state                             = "enabled"
  # instance_admin_state                    = "enabled"
  # access_list_match_local                 = "enabled"
  vrfs = {
     "vpc" = {

      interfaces = {
        "po4" = {

          addresses = {
            "1.1.1.2/30" = {

            }
          }
        }
      }
    }
  "xx01-xx-core" = {
    #   auto_discard                 = "enabled"
    #   icmp_errors_source_interface = "unspecified"
       static_routes = {
         "${local.loopback_octet}.5/32" = {
    #       control     = "bfd"
           description = "SR_TO_SAT01_LOOPBACK"
    #       preference  = 2
    #       tag         = 10
           next_hops = {
             "po2.3010;${local.xx01-xx-core_octet}.20;xx01-xx-core" = {
    #           description           = "My Description"
    #           object                = 10
    #           preference            = 123
    #           tag                   = 10
    #           name                  = "nh1"
    #           rewrite_encapsulation = "unknown"
             }
           }
         }
       }
      interfaces = {
        "lo101" = {

          addresses = {
            "${local.loopback_octet}.6/32" = {

            }
          }
        }
        "po2.3010" = {

          addresses = {
            "${local.xx01-xx-core_octet}.21/31" = {

            }
          }
        }
        "po12.3010" = {

          addresses = {
            "${local.xx01-xx-core_octet}.15/31" = {

            }
          }
        }
        "po22.3010" = {

          addresses = {
            "${local.xx01-xx-core_octet}.19/31" = {

            }
          }
        }
        "vlan650" = {

          addresses = {
            "${local.prod_xx_octet}.29/27" = {

            }
          }
        }
        "vlan651" = {

          addresses = {
            "${local.prod_xx_octet}.61/27" = {

            }
          }  
        }
      }
    }
  }
}
