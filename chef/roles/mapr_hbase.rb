name "mapr_hbase"
description "MapR HBase (Apache) Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::hbase]"
)
default_attributes(

)
