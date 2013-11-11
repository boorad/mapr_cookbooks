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


# get a list of the CLDB hostnames
cldbs = get_nodes_with_role_sp("cldb")
cldb_list = cldbs.reject(&:empty?).join(',')

# get a list of the ZooKeeper hostnames
zks = get_nodes_with_role_sp("zk")
zk_list = zks.reject(&:empty?).join(',')

execute 'configure.sh' do
  command "#{node[:mapr][:home]}/server/configure.sh -C #{cldb_list} -Z #{zk_list} -N #{node[:mapr][:clustername]}"
end
