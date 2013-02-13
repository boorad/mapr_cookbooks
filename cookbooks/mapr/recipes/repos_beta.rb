#
# Cookbook Name:: mapr
# Recipe:: repos-beta
#
# Copyright 2013, MapR Technologies
#

# TODO: DRY

if platform?("redhat", "centos")

  yum_repository "mapr_core" do
    creds = ""
    if node[:mapr][:beta_u]
      creds = "#{node[:mapr][:beta_u]}:#{node[:mapr][:beta_p]}@"
    end
    uri "http://#{creds}stage.mapr.com/beta/v3.0-beta/redhat"
  end

end

if platform?("ubuntu")

  apt_repository "mapr_core" do
    creds = ""
    if node[:mapr][:beta_u]
      creds = "#{node[:mapr][:beta_u]}:#{node[:mapr][:beta_p]}@"
    end
    uri "http://#{creds}stage.mapr.com/beta/v3.0-beta/ubuntu"
    notifies :run, resources(:execute => "apt-get update")
  end

end
