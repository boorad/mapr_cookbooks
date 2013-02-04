name "mapr_zookeeper"
description "MapR ZooKeeper Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::zookeeper]"
)
default_attributes(

)
