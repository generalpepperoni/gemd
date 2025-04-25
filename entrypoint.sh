#!/bin/bash

source /opt/ros/noetic/setup.bash
source /opt/gem_ws/devel/setup.bash
echo "source /opt/ros/noetic/setup.bash" >> /etc/profile.d/ros_env.sh
echo "source /opt/gem_ws/devel/setup.bash" >> /etc/profile.d/ros_env.sh

# Start roscore and forward log output
echo "Starting roscore..."
roscore > /var/log/ros/roscore_init.log 2>&1 &

# Wait briefly to ensure roscore is up
sleep 2
# This could be redefined in `rostopic list` ping
# but we will use similar logic in k8s pod healthcheck

# Add slight overhead, but enable rostopic statistics collection and Gazebo sim time
rosparam set enable_statistics true
rosparam set use_sim_time true

# Execute the passed command (e.g., bash, roslaunch)
exec "$@"
