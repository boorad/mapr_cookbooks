#
# Cookbook Name:: mapr
# Recipe:: fileserver
#
# Copyright 2013, MapR Technologies
#

package "mapr-fileserver" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
