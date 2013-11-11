#
# Cookbook Name:: mapr
# Recipe:: disable_services
#
# Copyright 2013, MapR Technologies
#

# disable zookeeper and warden services
service "mapr_zookeeper" do
  action :disable
end

service "mapr_warden" do
  action :disable
end
