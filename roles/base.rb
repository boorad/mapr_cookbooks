name "base"
description "base role"
run_list(
  "recipe[chef-client]",
  "recipe[mapr::user_root]",
  "recipe[emacs]"
)
default_attributes "chef_client" => {
  "server_url" => "http://chef.maprtech.com"
}
