#
# Cookbook Name:: mapr
# Recipe:: webserver
#
# Copyright 2013, MapR Technologies
#

# TODO: ajaxterm needed?

package "mapr-webserver" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
