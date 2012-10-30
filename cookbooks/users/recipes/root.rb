cookbook_file "/root/.bash_profile" do
  source "bash_profile"
  mode 0600
  owner "root"
  group "root"
end
