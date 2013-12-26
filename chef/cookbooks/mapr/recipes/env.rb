#
# Cookbook Name:: mapr
# Recipe:: env
#
# Copyright 2013, MapR Technologies
#

include_recipe "java::oracle"

template "#{node[:mapr][:home]}/conf/env.sh" do
  source "env.sh.erb"
  variables({
    :java_home => node[:java][:java_home],
    :mapr_subnets => node[:mapr][:mapr_subnets]
  })
end
