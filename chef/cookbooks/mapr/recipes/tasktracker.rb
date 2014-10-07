#
# Cookbook Name:: mapr
# Recipe:: tasktracker
#
# Copyright 2013, MapR Technologies
#

# a calculator program used by createTTVolume.sh
package "bc"

package "mapr-tasktracker" do
  options node[:mapr][:pkg_opts] unless node[:mapr][:pkg_opts].nil?
end
