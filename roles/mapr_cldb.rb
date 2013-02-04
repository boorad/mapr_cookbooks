name "mapr_cldb"
description "MapR Container Location Database Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::cldb]"
)
default_attributes(

)
