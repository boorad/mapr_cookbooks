name "mapr_base"
description "MapR Base Role"
run_list(
  "role[java]",
  "recipe[users::mapr]"
)
