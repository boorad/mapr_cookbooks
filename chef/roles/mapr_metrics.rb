name "mapr_metrics"
description "MapR Metrics Role"
run_list(
  "role[mapr_base]",
#  "recipe[mysql]",
  "recipe[mapr::metrics]"
)
default_attributes(

)
