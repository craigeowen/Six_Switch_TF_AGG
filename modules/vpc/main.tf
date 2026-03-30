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
  vpc_raw_yaml = yamldecode(file("${path.root}/vpc.yaml"))

  # Filter in the 'common_settings' block 
  # so Terraform uses only the common settings (vlans)

  vpc_data = { 
    for k, v in local.vpc_raw_yaml : k => v 
    if k != "common_settings" 
  }

# 2. Flatten: Create a map entry for every VPC on every device
  device_vpc = merge([
    for device_key, device_val in local.vpc_data: {
      for vpc_id, vpc_val in local.vpc_raw_yaml.common_settings.vpc :
      "${device_key}.${vpc_id}" => {
        device        = device_key
        #vlan_id      = try(vpc_id, "enabled") # This is a workaround to handle the case where vlan_id might not be present in the YAML")
        admin_state   = try(vpc_val.admin_state, "enabled")


      }
    }
  ]...) # The '...' is important to merge the list of maps into one map


  
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

##### Create VPC #####
resource "nxos_vpc" "vpc-agg01" {
  provider = nxos.twe-agg01
  domain_id = 101
  peer_switch = "enabled"
  role_priority = 10
  peer_gateway = "enabled"
  l3_peer_router = "enabled"
  auto_recovery = "enabled"
  auto_recovery_interval = 60
  admin_state = "enabled"
  peerlink_interface_id = "po1"  
  keepalive_destination_ip  = "1.1.1.2"
  keepalive_source_ip = "1.1.1.1"
  keepalive_vrf = "vpc"
  
}

resource "nxos_vpc" "vpc-agg02" {
  provider = nxos.twe-agg02
  domain_id = 101
  peer_switch = "enabled"
  role_priority = 10
  peer_gateway = "enabled"
  l3_peer_router = "enabled"
  auto_recovery = "enabled"
  auto_recovery_interval = 60
  admin_state = "enabled"
  peerlink_interface_id = "po1"  
  keepalive_destination_ip = "1.1.1.1"
  keepalive_source_ip = "1.1.1.2"
  keepalive_vrf = "vpc"
  
}

##### Required to add IP Arp sync to the vpc domain #####
# resource "nxos_dme" "Configure-vpc-dom-arp-inst-agg01" {
#   provider = nxos.twe-agg01
#   dn = "sys/arp/inst/vpc"
#   class_name = "arpVpc"
#   content = {

#   }
# }

resource "nxos_dme" "Configure-vpc-dom-arp" {
  for_each = local.vpc_data
  device = each.key 
  dn = "sys/arp/inst/vpc/dom-[101]"
  class_name = "arpVpcDom"
  content = {
    "arpSync": "enabled",
    "domainId": "101",
    "status": "created,modified"
  }
}

##### OUTPUT Module - will be used to return output to Root #####
# data "nxos_bridge_domain" "vlans_module" {
#   for_each = local.device_vlans
#   device = each.value.device
#   fabric_encap        = "vlan-${each.value.fabric_encap}"
# }

# output "vlans_module" {
#   value = data.nxos_bridge_domain.vlans_module
# }