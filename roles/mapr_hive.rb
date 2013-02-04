name "mapr_hive"
description "MapR Hive Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::hive]"
)
default_attributes(

)
