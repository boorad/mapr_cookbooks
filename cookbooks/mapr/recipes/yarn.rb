#
# Cookbook Name:: mapr
# Recipe:: yarn
#
# Copyright 2013, MapR Technologies
#

#package "mapr-yarn"

for i in 1..4

  # set up yarn local folders
  directory "/data/#{i}/yarn/local" do
    owner node['mapr']['user']
    group node['mapr']['group']
    action :create
    recursive true
    mode 0755
  end

  # set up yarn log folders
  directory "/data/#{i}/yarn/logs" do
    owner node['mapr']['user']
    group node['mapr']['group']
    action :create
    recursive true
    mode 0755
  end

end

# because of http://tickets.opscode.com/browse/CHEF-1621
execute "chown_mapr" do
  command "chown -R #{node[:mapr][:user]}:#{node[:mapr][:group]} /data"
  action :run
end

# init script
template "#{node[:mapr][:home]}/initscripts/mapr-nodemanager" do
  source "mapr-nodemanager"
  mode 0755
end

link "/etc/init.d/mapr-nodemanager" do
  to "#{node[:mapr][:home]}/initscripts/mapr-nodemanager"
end
