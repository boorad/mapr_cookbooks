#
# Cookbook Name:: mapr
# Recipe:: hive
#
# Copyright 2013, MapR Technologies
#

package "mapr-hive" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
