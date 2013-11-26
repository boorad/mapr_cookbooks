name "mapr_base"
description "MapR Base Role"
run_list(
  "role[java]",
  "recipe[ntp]",
  "recipe[iptables]",
  "recipe[mapr::hostname]",
  "recipe[hostname]",
  "recipe[mapr::user_mapr]",
  "recipe[mapr::dns]",
  "recipe[mapr::ulimit]",
  "recipe[mapr::iptables]",
  "recipe[mapr::pam]",
  "recipe[mapr::ssh]",
  "recipe[mapr::clush]",
  "recipe[mapr::repos]"
)
default_attributes(

)
