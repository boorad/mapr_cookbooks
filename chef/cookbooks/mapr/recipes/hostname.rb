#
# Cookbook Name:: mapr
# Recipe:: hostname
#
# Copyright 2013, MapR Technologies
#

node.default[:set_fqdn] = node[:mapr][:node][:fqdn]
