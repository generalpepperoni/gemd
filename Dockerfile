FROM osrf/ros:noetic-desktop-full AS gem-base
LABEL authors="aleksei.kondrashov94@gmail.com"
ENV SRC_URL=https://github.com/generalpepperoni/POLARIS_GEM_e2/archive/refs/heads/devel.zip

RUN apt update \
    && apt install -yq --no-install-recommends software-properties-common \
    && apt install -yq \
       ros-noetic-ackermann-msgs ros-noetic-geometry2 \
       ros-noetic-hector-gazebo ros-noetic-hector-models \
       ros-noetic-ros-control ros-noetic-ros-controllers \
       ros-noetic-jsk-rviz-plugins ros-noetic-velodyne-simulator \
       unzip \
    && apt autoremove -yqq --purge \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# Init a /var/log dir for custom ros logs
RUN mkdir -p /var/log/ros

# Create a workspace and copy ROS packages and GEM src
RUN mkdir -p /opt/gem_ws/src

# TODO: publish GEM sources in .tar.gz as GitHub Release artifact
# it will save some build time
ADD $SRC_URL /tmp/gem_src.zip
RUN unzip /tmp/gem_src.zip -d /opt/gem_ws/src \
    && rm /tmp/gem_src.zip

WORKDIR /opt/gem_ws
SHELL ["/bin/bash", "-c"]
RUN source /opt/ros/noetic/setup.bash && catkin_make

COPY entrypoint.sh /opt/entrypoint.sh
COPY healthcheck.sh /opt/healthcheck.sh
RUN chmod +x /opt/entrypoint.sh /opt/healthcheck.sh

# Source ROS in the .bashrc
RUN echo "source /opt/ros/noetic/setup.bash" >> /root/.bashrc \
    && echo "source devel/setup.bash" >> /root/.bashrc


ENTRYPOINT ["/opt/entrypoint.sh"]
CMD roslaunch gem_gazebo gem_gazebo_rviz.launch velodyne_points:='true'


# docker target with additional pkgs enabled X11 for developers` PCs
FROM gem-base AS gem-desktop
# Set environment variables for developers` GUI (e.g. for Gazebo. rviz, rqt_graph, etc.)
ENV DISPLAY=:0
ENV QT_X11_NO_MITSHM=1

# common dev tools and gazebo11 pkgs
RUN add-apt-repository universe \
    && apt update -yq \
    && apt install -yq --no-install-recommends \
       git coreutils zip tree tar tzdata curl jq vim nano mc ncdu htop iotop atop screen \
       gazebo11 ros-noetic-gazebo-ros-pkgs ros-noetic-gazebo-ros-control \
    && apt autoremove -yqq --purge \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# TODO: for development purpose, consider to use GEM simulator from submodule
COPY . /opt/gemd
WORKDIR /opt/gemd
RUN git submodule update
# Fallback to catkin workspace from base img
WORKDIR /opt/gem_ws


# docker target with additional pkgs for building custom ROS pkgs
FROM gem-base AS gem-build
RUN apt install -y -q \
       build-essential \
       python3-rosdep \
       python3-rosinstall \
       python3-rosinstall-generator \
       python3-wstool \
    && apt clean \
    && apt autoremove -yqq --purge \
    && rm -rf /var/lib/apt/lists/*

RUN rosdep init  \
    && rosdep update
