#
# Cookbook Name:: mapr
# Recipe:: iptables
#
# Copyright 2013, MapR Technologies
#

# firewall
if platform_family?("rhel")
  iptables_rule "mapr_ports"
end
