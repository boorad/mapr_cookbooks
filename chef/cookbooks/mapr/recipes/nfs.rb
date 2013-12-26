#
# Cookbook Name:: mapr
# Recipe:: nfs
#
# Copyright 2013, MapR Technologies
#

# MapR package
package "mapr-nfs"


# supporting packages
if platform_family?("rhel")
  package "nfs-utils"
end

if platform_family?("debian")
  package "nfs-common"
end

if platform_family?("suse")
  package "nfs-client"
end


# rpcbind
package "rpcbind"

service "rpcbind" do
  action :enable
  action :restart
end
