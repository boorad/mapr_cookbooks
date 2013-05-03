name "mapr_hbase_dbclient"
description "MapR HBase Client (M7) Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::hbase-dbclient]"
)
default_attributes(

)
