name "mapr_beta"
description "MapR Beta Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::repos_beta]"
)
default_attributes(

)
