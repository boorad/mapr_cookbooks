name "base"
description "base role"
run_list(
  "recipe[chef-client]",
  "recipe[users::root]",
  "recipe[emacs]"
)
default_attributes "chef_client" => {
  "server_url" => "http://chef.maprtech.com"
}
