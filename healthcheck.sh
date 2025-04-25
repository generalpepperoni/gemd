#!/bin/bash
# Listing rostopics to verify is roscore is alive
# Exit code 0 = healthy, 1 = unhealthy
source /opt/ros/noetic/setup.bash
rostopic list &>/dev/null
exit $?
