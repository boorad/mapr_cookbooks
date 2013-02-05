#
# Cookbook Name:: mapr
# Recipe:: fileserver
#
# Copyright 2013, MapR Technologies
#

package "mapr-fileserver"

execute "disksetup" do
  command "/opt/mapr/server/disksetup -F /tmp/disks.txt"
  action :nothing
end

template "/tmp/disks.txt" do
  source "disks.erb"
  variables({
    :disks => node[:mapr][:disks]
  })
  notifies :run, resources(:execute => "disksetup"), :immediately
end
