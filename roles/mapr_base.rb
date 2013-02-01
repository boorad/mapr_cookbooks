name "mapr_base"
description "MapR Base Role"
run_list(
  "role[java]",
  "recipe[ntp]",
  "recipe[hostname]",
#  "recipe[chef-solo-search]",
#  "recipe[hosts-awareness]",
  "recipe[users::mapr]",
  "recipe[mapr::dns]",
  "recipe[mapr::ulimit]",
  "recipe[mapr::ssh]"
)
default_attributes(

)
