name "mapr_mahout"
description "MapR Mahout Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::mahout]"
)
default_attributes(

)
