#
# Cookbook Name:: mapr
# Recipe:: dns
#
# Copyright 2013, MapR Technologies
#

# present on Vagrant box
hostsfile_entry '127.0.1.1' do
  action :remove
end


# nodes in cluster
nodes = search(:node, "*:*")

nodes.each do |n|

  hostsfile_entry n[:mapr][:ip] do
    hostname n[:mapr][:host]
    aliases [n[:mapr][:fqdn]]
    action :create
  end

end
