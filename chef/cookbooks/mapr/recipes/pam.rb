#
# Cookbook Name:: mapr
# Recipe:: pam
#
# Copyright 2013, MapR Technologies
#

template "/etc/pam.d/mapr-admin" do
  source "pam-mapr-admin.erb"
end
