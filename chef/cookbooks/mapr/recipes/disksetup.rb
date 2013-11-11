#
# Cookbook Name:: mapr
# Recipe:: disksetup
#
# Copyright 2013, MapR Technologies
#

##
## disksetup
##

# TODO: test for if this node has mapr_fileserver role

# note, we use the conf/ directory here, because often /tmp/disks.txt is cleared
# out upon reboot, and we don't want to necessarily fire off disksetup if that
# file can't be found.

execute "disksetup" do
  command "#{node[:mapr][:home]}/server/disksetup -F #{node[:mapr][:home]}/conf/disks.txt"
  action :nothing
end

template "#{node[:mapr][:home]}/conf/disks.txt" do
  source "disks.erb"
  variables({
    :disks => node[:mapr][:node][:disks]
  })
  notifies :run, resources(:execute => "disksetup"), :immediately
end
