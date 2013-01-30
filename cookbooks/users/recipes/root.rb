cookbook_file "/root/.bashrc" do
  source "bashrc"
  mode 0600
  owner "root"
  group "root"
end
