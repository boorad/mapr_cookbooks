#
# Cookbook Name:: mapr
# Recipe:: ulimit
#
# Copyright 2013, MapR Technologies
#

template "/etc/security/limits.d/root_limits.conf" do
  source "root_limits.erb"
end
