#
# Cookbook Name:: mapr
# Recipe:: iptables
#
# Copyright 2013, MapR Technologies
#

# firewall
if platform?("redhat", "centos")

  iptables_rule "mapr_ports"

end
