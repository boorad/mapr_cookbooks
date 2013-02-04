name "mapr_tasktracker"
description "MapR TaskTracker Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::tasktracker]"
)
default_attributes(

)
