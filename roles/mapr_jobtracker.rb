name "mapr_jobtracker"
description "MapR JobTracker Role"
run_list(
  "role[mapr_base]",
  "recipe[mapr::jobtracker]"
)
default_attributes(

)
