name "mapr_yarn"
description "MapR YARN Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::yarn]"
)
default_attributes(

)
