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
  #raw_yaml = yamldecode(file("${path.root}/vlans.yaml"))
  raw_yaml = yamldecode(file(("${path.module}/../yaml_configs/switching.yaml"))) 

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

  # 3. Flattening Logic:
  # Since 'for_each' can only loop over a single-level map, we must 
  # transform the nested structure (Switch -> vpc) into a flat map.
  device_vpc = {
    for device_key, device_val in local.device_list : device_key => {
      device_name    = device_key
      # Use try() to look into the features map, defaulting to null if not present
      domain_id                = try(device_val.vpc.domain_id, null)
      admin_state              = try(device_val.vpc.admin_state, null)
      peer_switch              = try(device_val.vpc.peer_switch, null)
      role_priority            = try(device_val.vpc.role_priority, null)
      peer_gateway             = try(device_val.vpc.peer_gateway, null)
      l3_peer_router           = try(device_val.vpc.l3_peer_router, null)
      auto_recovery            = try(device_val.vpc.auto_recovery, null)
      auto_recovery_interval   = try(device_val.vpc.auto_recovery_interval, null)
      peerlink_interface_id    = try(device_val.vpc.peerlink_interface_id, null)  
      keepalive_destination_ip = try(device_val.vpc.keepalive_destination_ip, null)
      keepalive_source_ip      = try(device_val.vpc.keepalive_source_ip, null)
      keepalive_vrf            = try(device_val.vpc.keepalive_vrf, null)
    }
  }

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

resource "nxos_vpc" "vpc" {
    for_each = local.device_vpc
    device = each.value.device_name
    admin_state                                  = "${each.value.admin_state}"
    domain_id                                    = "${each.value.domain_id}"
    auto_recovery                                = "${each.value.auto_recovery}"
    auto_recovery_interval                       = "${each.value.auto_recovery_interval}"
    l3_peer_router                               = "${each.value.l3_peer_router}"
    peer_gateway                                 = "${each.value.peer_gateway}"
    peer_switch                                  = "${each.value.peer_switch}"
    role_priority                                = "${each.value.role_priority}"
    keepalive_destination_ip                     = "${each.value.keepalive_destination_ip}"
    keepalive_source_ip                          = "${each.value.keepalive_source_ip}"
    keepalive_vrf                                = "${each.value.keepalive_vrf}"
    peerlink_interface_id                        = "${each.value.peerlink_interface_id}"
#    peerlink_admin_state                         = "enabled"
#  interfaces = {
#    "1" = {
#      port_channel_interface_dn = "sys/intf/aggr-[po1]"
#    }
#  }
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
  for_each = local.device_list
  device = each.key 
  dn = "sys/arp/inst/vpc/dom-[101]"
  class_name = "arpVpcDom"
  content = {
    "arpSync": "enabled",
    "domainId": "101",
    "status": "created,modified"
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