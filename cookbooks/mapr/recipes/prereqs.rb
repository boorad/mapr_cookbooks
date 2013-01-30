#
# Cookbook Name:: mapr
# Recipe:: prereqs
#
# Copyright 2013, MapR Technologies
#

# DNS
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

# ulimit
template "/etc/security/limits.d/root_limits.conf" do
  source "root_limits.erb"
end

template "/etc/pam.d/su" do
  source "su.erb"
end

#
