#
# Cookbook Name:: mapr
# Recipe:: dns
#
# Copyright 2013, MapR Technologies
#

# nodes in cluster
cluster = data_bag_item("cluster","cluster")

nodes = cluster['nodes']

nodes.each do |n|

  hostsfile_entry n['ip'] do
    hostname n['host']
    aliases [n['fqdn']]
    action :create
  end

end
