name "mapr_configure"
description "MapR Configure Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::configure]"
)
default_attributes(

)
