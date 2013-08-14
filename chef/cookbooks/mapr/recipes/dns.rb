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
#nodes = search(:node, "*:*")

node[:mapr][:nodes].each do |n|

  hostsfile_entry n[:ip] do
    hostname n[:host]
    aliases [n:[fqdn]]
    action :create
  end

end
