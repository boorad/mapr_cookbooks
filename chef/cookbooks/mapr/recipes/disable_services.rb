#
# Cookbook Name:: mapr
# Recipe:: disable_services
#
# Copyright 2013, MapR Technologies
#

# disable zookeeper and warden services
service "mapr-zookeeper" do
  action :disable
  only_if {File.exists?("/etc/init.d/mapr-zookeeper")}
end

service "mapr-warden" do
  action :disable
end
