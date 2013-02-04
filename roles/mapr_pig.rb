name "mapr_pig"
description "MapR Pig Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::pig]"
)
default_attributes(

)
