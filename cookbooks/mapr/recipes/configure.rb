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
def get_nodes_with_role(role)
    nodes = []
    role_nodes = search(:node, "role:#{role}")

    role_nodes.each do |n|
      nodes.push(n[:mapr][:fqdn])
    end

    nodes
end

# get a list of the CLDB hostnames
cldbs = get_nodes_with_role("mapr_cldb")
cldb_list = cldbs.reject(&:empty?).join(',')

# get a list of the ZooKeeper hostnames
zks = get_nodes_with_role("mapr_zookeeper")
zk_list = zks.reject(&:empty?).join(',')

execute 'configure.sh' do
  command "#{node[:mapr][:home]}/server/configure.sh -C #{cldb_list} -Z #{zk_list} -N #{node[:mapr][:clustername]}"
end


##
## disksetup
##

# TODO: test for if this node has mapr_fileserver role

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
