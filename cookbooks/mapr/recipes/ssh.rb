log "=========== Start MapR ssh.rb ============="

#######################
# Keys for MapR user

directory "/home/#{node['mapr']['user']}/.ssh" do
  owner  node['mapr']['user']
  group  node['mapr']['group']
  mode "700"
end

cookbook_file "/home/#{node['mapr']['user']}/.ssh/authorized_keys" do
  owner  node['mapr']['user']
  group  node['mapr']['group']
  mode "644"
  source "id_rsa_maprtemp.pub"
end

cookbook_file "/home/#{node['mapr']['user']}/.ssh/id_rsa" do
  owner  node['mapr']['user']
  group  node['mapr']['group']
  mode "600"
  source "id_rsa_maprtemp"
end

cookbook_file "/home/#{node['mapr']['user']}/.ssh/config" do
  source "ssh_config"
  owner  node['mapr']['user']
  group  node['mapr']['group']
  mode "644"
end
