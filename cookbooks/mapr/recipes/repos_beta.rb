#
# Cookbook Name:: mapr
# Recipe:: repos-beta
#
# Copyright 2013, MapR Technologies
#

if platform?("redhat", "centos")

  yum_repository "mapr_core" do
    uri "http://yum.qa.lab/mapr-beta"
  end

end

if platform?("ubuntu")

  apt_repository "mapr_core" do
    uri "http://apt.qa.lab/mapr-beta"
  end

end
