#
# Cookbook Name:: mapr
# Recipe:: zookeeper
#
# Copyright 2013, MapR Technologies
#

package "mapr-zookeeper" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
