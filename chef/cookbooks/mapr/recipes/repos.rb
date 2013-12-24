#
# Cookbook Name:: mapr
# Recipe:: repos
#
# Copyright 2013, MapR Technologies
#

# TODO: check for valid versions and alert to bad ones
version = "v#{node['mapr']['version']}"


if platform_family?("rhel")

  yum_repository "mapr_core" do
    url "#{node['mapr']['repo_url']}/#{version}/redhat"
  end

  yum_repository "mapr_ecosystem" do
    url "#{node['mapr']['repo_url']}/ecosystem/redhat"
  end

end

if platform_family?("debian")

  include_recipe "apt"

  apt_repository "mapr_core" do
    uri "#{node['mapr']['repo_url']}/#{version}/#{node['platform']}"
    distribution "mapr"
    components ["optional"]
    notifies :run, resources(:execute => "apt-get update")
  end

  apt_repository "mapr_ecosystem" do
    uri "#{node['mapr']['repo_url']}/ecosystem/#{node['platform']}"
    components ["binary/"]
    notifies :run, resources(:execute => "apt-get update")
  end

end
