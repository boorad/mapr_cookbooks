#
# Cookbook Name:: mapr
# Recipe:: enable_services
#
# Copyright 2013, MapR Technologies
#

# enable zookeeper and warden services
service "mapr_zookeeper" do
  action :enable
end

service "mapr_warden" do
  action :enable
end
