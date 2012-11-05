name "mapr_base"
description "MapR Base Role"
run_list(
  "role[java]",
  "recipe[users::mapr]",
  "recipe[ntp]"
)
default_attributes(
  "ntp" => {
    "servers" => ["0.pool.ntp.org", "1.pool.ntp.org"]
  }
)
