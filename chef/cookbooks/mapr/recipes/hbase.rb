#
# Cookbook Name:: mapr
# Recipe:: hbase
#
# Copyright 2013, MapR Technologies
#

package "mapr-hbase" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
