name "mapr_base"
description "MapR Base Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::repos_beta]"
)
default_attributes(

)
