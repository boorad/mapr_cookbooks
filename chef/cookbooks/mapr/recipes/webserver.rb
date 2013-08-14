#
# Cookbook Name:: mapr
# Recipe:: webserver
#
# Copyright 2013, MapR Technologies
#

# TODO: ajaxterm needed?

package "mapr-webserver" do
  options "--allow-unauthenticated"
end
