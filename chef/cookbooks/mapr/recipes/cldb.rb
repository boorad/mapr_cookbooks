#
# Cookbook Name:: mapr
# Recipe:: cldb
#
# Copyright 2013, MapR Technologies
#

package "mapr-cldb" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
