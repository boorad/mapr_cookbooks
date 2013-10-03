#
# Cookbook Name:: mapr
# Recipe:: configure
#
# Copyright 2013, MapR Technologies
#

##
## configure.sh
##

# TODO: move this to shared lib?
def get_nodes_with_role_sp(role)
    nodes = []
    if role == ""
      role = "all"
    end
    role_nodes = node[:mapr][:groups][role]

    role_nodes.each do |n|
      nodes.push(n)
    end

    nodes
end

# disable zookeeper and warden services until after configuration is complete
service "mapr_zookeeper" do
  action :disable
end

service "mapr_warden" do
  action :disable
end


# get a list of the CLDB hostnames
cldbs = get_nodes_with_role_sp("cldb")
cldb_list = cldbs.reject(&:empty?).join(',')

# get a list of the ZooKeeper hostnames
zks = get_nodes_with_role_sp("zk")
zk_list = zks.reject(&:empty?).join(',')

execute 'configure.sh' do
  command "#{node[:mapr][:home]}/server/configure.sh -C #{cldb_list} -Z #{zk_list} -N #{node[:mapr][:clustername]}"
end


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
