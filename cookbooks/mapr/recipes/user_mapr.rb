group node['mapr']['group'] do
  gid node['mapr']['gid']
end

user node['mapr']['user'] do
  uid node['mapr']['uid']
  gid node['mapr']['gid']
  shell "/bin/bash"
  home "/home/#{node['mapr']['user']}"
end

directory "/home/#{node['mapr']['user']}" do
  owner node['mapr']['user']
  group node['mapr']['group']
  mode 0700
end

cookbook_file "/home/#{node['mapr']['user']}/.bashrc" do
  source "bashrc"
  mode 0600
  owner node['mapr']['user']
  group node['mapr']['group']
end
