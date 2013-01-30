name "mapr_base"
description "MapR Base Role"
run_list(
  "role[java]",
  "recipe[ntp]",
  "recipe[hostname]",
  "recipe[users::mapr]",
  "recipe[mapr::dns]",
  "recipe[mapr::ulimit]",
  "recipe[mapr::ssh]"
)
default_attributes(
  "ntp" => {
    "servers" => ["0.pool.ntp.org", "1.pool.ntp.org"]
  }
)
