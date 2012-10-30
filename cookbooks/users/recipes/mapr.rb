group "mapr" do
  gid 500
end

user "mapr" do
  uid 500
  gid 500
  shell "/bin/bash"
  home "/home/mapr"
end

directory "/home/mapr" do
  owner "mapr"
  group "mapr"
  mode 0700
end

cookbook_file "/home/mapr/.bash_profile" do
  source "bash_profile"
  mode 0600
  owner "mapr"
  group "mapr"
end
