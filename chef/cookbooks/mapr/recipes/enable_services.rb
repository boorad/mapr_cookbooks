#
# Cookbook Name:: mapr
# Recipe:: enable_services
#
# Copyright 2013, MapR Technologies
#

# enable zookeeper and warden services
service "mapr-zookeeper" do
  action [ :enable, :stop ]
  only_if {File.exists?("/etc/init.d/mapr-zookeeper")}
end

service "mapr-warden" do
  action [ :enable, :stop ]
end
