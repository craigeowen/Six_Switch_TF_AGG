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

  interface_yaml = yamldecode(file("${path.root}/interface.yaml"))

  # Filter in the 'common_settings' block 
  # so Terraform uses only the common settings (vlans)

  device_data = { 
    for k, v in local.raw_yaml : k => v 
    if k != "common_settings" 
  }

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


##### Physical Interfaces #####

### Required to bring up PO1 physical interfaces as they are part of the vPC keepalive configuration. The port-channel interface will not come up without the physical interface being up and in the correct state. This is a workaround to ensure the PO4 interfaces come up and we can then remove this code and manage the physical interfaces in a seperate module if desired.
resource "nxos_physical_interface" "eth1_7_8" {
  for_each = local.device_data
  device = each.key 
  physical_interfaces = {
        "eth1/7"= {
        admin_state                        = "up"
        description                        = "PO1_Member"
        }
        "eth1/8"= {
        admin_state                        = "up"
        description                        = "PO1_Member"
        }
  }
}

### Required to bring up PO2 physical interfaces as they are part of the vPC keepalive configuration. The port-channel interface will not come up without the physical interface being up and in the correct state. This is a workaround to ensure the PO4 interfaces come up and we can then remove this code and manage the physical interfaces in a seperate module if desired.
resource "nxos_physical_interface" "eth1_10_12" {
  for_each = local.device_data
  device = each.key
  physical_interfaces = {
    "eth1/10" = {
      admin_state                        = "up"
      description                        = "PO2_Member"
    }
    "eth1/12" = {
      admin_state                        = "up"
      description                        = "PO2_Member"
    }
  }
}

### Required to bring up PO4 physical interfaces as they are part of the vPC keepalive configuration. The port-channel interface will not come up without the physical interface being up and in the correct state. This is a workaround to ensure the PO4 interfaces come up and we can then remove this code and manage the physical interfaces in a seperate module if desired.
resource "nxos_physical_interface" "eth1_6" {
  for_each = local.device_data
  device = each.key 
  physical_interfaces = {
        "eth1/6" = {
        admin_state                        = "up"
        description                        = "PO4_Member"
        }
        
  }
}



# resource "nxos_physical_interface" "eth1_6" {
#   for_each = local.device_data
#   device = each.key 
#   physical_interfaces = {
#     "eth1/6" = {
#       admin_state                        = "up"
#       description                        = "PO1_Memnber"
#       layer                              = "Layer2"
#       mode                               = "access"
#       mtu                                = 1500
#       trunk_vlans                        = "1-4094"
#     }
#   }
# }

##### Physical Interfaces #####

##### Port-Channel Interfaces #####



resource "nxos_port_channel_interface" "po-agg01" {
  provider = nxos.twe-agg01
  #for_each = local.device_data
  #device = each.key 
  port_channel_interfaces = {
    "po1" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      suspend_individual     = "disable"
      admin_state            = "up"
      description            = "### vPC peer-link ###"
      layer                  = "Layer2"
      mode                   = "trunk"
      mtu                    = 1500
      trunk_vlans            = "1-4094"
      members = {
        "sys/intf/phys-[eth1/7]" = {
          force = true
        }
        "sys/intf/phys-[eth1/8]" = {
          force = true
        }
      }
    }
    "po2" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### TWE Peer Routed Connectivity ###"
      layer                  = "Layer3"
      mtu                    = 9216
      members = {
        "sys/intf/phys-[eth1/10]" = {
          force = true
        }
        "sys/intf/phys-[eth1/12]" = {
          force = true
        }
      }
    }
     "po4" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### VPC Keepalive ###"
      layer                  = "Layer3"
      mtu                    = 9216
      vrf_dn       = "sys/inst-vpc"
      members = {
        "sys/intf/phys-[eth1/6]" = {
          force = true
        }

      }
    }
    "po11" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### TWE 01 to SAT 01 ###"
      layer                  = "Layer3"
      mtu                    = 9216
      members = {
        "sys/intf/phys-[eth1/1]" = {
          force = true
        }
        
      }
    }
     "po12" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### TWE AGG01 to SAT 02 ###"
      layer                  = "Layer3"
      mtu                    = 9216
      members = {
        "sys/intf/phys-[eth1/2]" = {
          force = true
        }

      }
    }
  }
}

resource "nxos_port_channel_interface" "po-agg02" {
  provider = nxos.twe-agg02
  #for_each = local.device_data
  #device = each.key 
  port_channel_interfaces = {
    "po1" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      suspend_individual     = "disable"
      admin_state            = "up"
      description            = "### vPC peer-link ###"
      layer                  = "Layer2"
      mode                   = "trunk"
      mtu                    = 1500
      trunk_vlans            = "1-4094"
      members = {
        "sys/intf/phys-[eth1/7]" = {
          force = true
        }
        "sys/intf/phys-[eth1/8]" = {
          force = true
        }
      }
    }
    "po2" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### TWE Peer Routed Connectivity ###"
      layer                  = "Layer3"
      mtu                    = 9216
      members = {
        "sys/intf/phys-[eth1/10]" = {
          force = true
        }
        "sys/intf/phys-[eth1/12]" = {
          force = true
        }
      }
    }
     "po4" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### VPC Keepalive ###"
      layer                  = "Layer3"
      mtu                    = 9216
      vrf_dn       = "sys/inst-vpc"
      members = {
        "sys/intf/phys-[eth1/6]" = {
          force = true
        }

      }
    }
    "po21" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### TWE 01 to SAT 01 ###"
      layer                  = "Layer3"
      mtu                    = 9216
      members = {
        "sys/intf/phys-[eth1/1]" = {
          force = true
        }
        
      }
    }
     "po22" = {
      port_channel_mode      = "active"
      minimum_links          = 1
      admin_state            = "up"
      description            = "### TWE AGG01 to SAT 02 ###"
      layer                  = "Layer3"
      mtu                    = 9216
      members = {
        "sys/intf/phys-[eth1/2]" = {
          force = true
        }

      }
    }
  }
}

##### End of Port-Channel Interfaces #####

##### Loopback Interfaces #####

resource "nxos_loopback_interface" "lo101" {
  for_each = local.device_data
  device = each.key   
  loopback_interfaces = {
    "lo101" = {
      admin_state  = "up"
      description  = "### XX01-Loopback ###"
      #link_logging = "enable"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
  }
}


##### End of Loopback Interfaces #####

##### Sub Interfaces #####

resource "nxos_subinterface" "subint-sag01" {
    provider = nxos.twe-agg01
    subinterfaces = {
    "po2.3010" = {
      admin_state  = "up"
      description  = "### XX-01 AGG to AGG iBGP ###"
      mtu          = 9216
      encap        = "vlan-3010"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
    "po11.3010" = {
      admin_state  = "up"
      description  = "### XX-01 AGG to AGG iBGP ###"
      mtu          = 9216
      encap        = "vlan-3010"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
    "po12.3010" = {
      admin_state  = "up"
      description  = "### XX-01 AGG to AGG iBGP ###"
      mtu          = 9216
      encap        = "vlan-3010"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
  }
}

resource "nxos_subinterface" "subint-sag02" {
    provider = nxos.twe-agg02
    subinterfaces = {
    "po2.3010" = {
      admin_state  = "up"
      description  = "### XX-01 AGG to AGG iBGP ###"
      mtu          = 9216
      encap        = "vlan-3010"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
    "po21.3010" = {
      admin_state  = "up"
      description  = "### XX-01 AGG to AGG iBGP ###"
      mtu          = 9216
      encap        = "vlan-3010"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
    "po22.3010" = {
      admin_state  = "up"
      description  = "### XX-01 AGG to AGG iBGP ###"
      mtu          = 9216
      encap        = "vlan-3010"
      vrf_dn       = "sys/inst-xx01-xx-core"
    }
  }
}

##### End of Sub Interfaces #####

##### SVI Interfaces ##### 

#resource "nxos_svi_interface" "example" {
#   for_each = local.device_data
#   device = each.key 
#   svi_interfaces = {
#     "vlan650" = {
#       admin_state             = "up"
#       description            = "### XX-01_XXX_PROD_XX_OUTSIDE ###"
#       mtu                     = 9216
#       vrf_dn                  = "sys/inst-xx01-xx-core"
#     }
#     "vlan651" = {
#       admin_state             = "up"
#       description            = "### XX-01_XXX_PROD_XX_INSIDE ###"
#       mtu                     = 9216
#       vrf_dn                  = "sys/inst-xx01-xx-core"
#     }
#   }
# }


##### End of SVI Interfaces #####