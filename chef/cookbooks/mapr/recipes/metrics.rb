#
# Cookbook Name:: mapr
# Recipe:: metrics
#
# Copyright 2013, MapR Technologies
#

package "mapr-metrics" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
