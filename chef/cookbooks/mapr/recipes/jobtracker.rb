#
# Cookbook Name:: mapr
# Recipe:: jobtracker
#
# Copyright 2013, MapR Technologies
#

package "mapr-jobtracker" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
