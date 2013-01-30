#
# Cookbook Name:: mapr
# Recipe:: dns
#
# Copyright 2013, MapR Technologies
#

hostsfile_entry '127.0.0.1' do
  action :remove
end

hostsfile_entry '127.0.1.1' do
  action :remove
end

hostsfile_entry '127.0.0.1' do
  hostname node[:set_fqdn]
  aliases ["localhost", "localhost.localdomain"]
  action :create
end
