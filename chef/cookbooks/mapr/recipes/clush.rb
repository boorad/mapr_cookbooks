#
# Cookbook Name:: mapr
# Recipe:: clush (clustershell)
#
# Copyright 2013, MapR Technologies
#

# TODO: move this to shared lib?
def get_nodes_with_role_sp(role)
    nodes = []
    if role == ""
      query = "*"
    else
      query = "role:#{role}"
    end
    role_nodes = search(:node, query)

    role_nodes.each do |n|
      nodes.push(n[:mapr][:host])
    end

    nodes.reject(&:empty?).join(' ')
end

if platform?("redhat", "centos")
  include_recipe "yum::epel"
end

package "clustershell"

all = get_nodes_with_role_sp("")
cldb = get_nodes_with_role_sp("mapr_cldb")
zk = get_nodes_with_role_sp("mapr_zookeeper")
jt = get_nodes_with_role_sp("mapr_jobtracker")
tt = get_nodes_with_role_sp("mapr_tasktracker")

# groups file
template "/etc/clustershell/groups" do
  source "clustershell.groups.erb"
  variables({
    :all => all,
    :cldb => cldb,
    :zk => zk,
    :jt => jt,
    :tt => tt,
  })
  mode 0644
end
