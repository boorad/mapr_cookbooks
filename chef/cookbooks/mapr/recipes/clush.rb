#
# Cookbook Name:: mapr
# Recipe:: clush (clustershell)
#
# Copyright 2013, MapR Technologies
#

if platform?("redhat", "centos")
  include_recipe "yum::epel"
end

package "clustershell"
