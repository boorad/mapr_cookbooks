#
# Cookbook Name:: mapr
# Recipe:: hbase-dbclient
#
# Copyright 2013, MapR Technologies
#

package "mapr-hbase-dbclient" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
