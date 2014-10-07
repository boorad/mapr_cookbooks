#
# Cookbook Name:: mapr
# Recipe:: pig
#
# Copyright 2013, MapR Technologies
#

package "mapr-pig" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
