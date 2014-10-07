#
# Cookbook Name:: mapr
# Recipe:: mahout
#
# Copyright 2013, MapR Technologies
#

package "mapr-mahout" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
