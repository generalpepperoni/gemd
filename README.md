# GEMd - Dockerized Polaris GEM E2 simulator
This project aims to provide the Polaris GEM E2 simulator (ROS 1 Noetic) in all-rounded Docker environment,
for a modern local development and cloud-native envirnoments.

Polaris GEM E2 simulator originally developed at Center for Autonomy at University of Illinois at Urbana-Champaign:  
https://gitlab.engr.illinois.edu/gemillins/POLARIS_GEM_e2

GEMd project uses GitHub fork of above repository:  
https://github.com/generalpepperoni/POLARIS_GEM_e2


## NABC Analysis: Modernizing the Polaris GEM e2 Simulator  

| NABC            | Analysis |  
|-----------------|----------|  
| **Needs**       | - ROS 1 Noetic & Ubuntu 20.04 reach EOL in Q2 2025 <br> - Using legacy stack could be tricky and vulnerable |  
| **Approach**    | - Full-fledged ROS + GEM e2 simulator  <br> - Optimized for GPU GUI ROS tools |  
| **Benefits**    | - **Ecosystem**: Free and easy-to-use simulator  <br> - **Easier adoption**: Good for ROS onboarding  <br> - **Performance**: Leverages modern hardware  <br> |  
| **Competitors** | - **Paid** Ubuntu Pro for 20.04 ESM  <br> - **Other ROS simulators** (e.g., AWSIM, Webots) |  


## Environment setup
Clone sources:
```shell
git clone --recurse-submodules https://github.com/generalpepperoni/gemd.git
# OR you can update submodule separately
git clone https://github.com/generalpepperoni/gemd.git
git submodule update --init --remote
```


### Local development setup (with X11 ROS GUI application support)
Tested on Ubuntu 24.04 (noble) and 20.04.2 (focal)

At first, allow access to the host`s X11 server:
```shell
xhost +local:root
```

Build GEMd image on local machine:
```shell
docker build --target gem-desktop --tag gemd-desktop:local .
```

Run GEMd container with X11 GUI application support:
```shell
docker run --rm -it \
    --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw" \
    --volume="$HOME/.Xauthority:/root/.Xauthority:rw" \
    --network=host \
    --name gemd \
    gemd-desktop:local
    # In case of skipped local build, run container directly from ghcr.io image
    #ghcr.io/generalpepperoni/gemd-desktop:latest
```


### Headless slim setup (e.g. for CI applications)

GEMd can run in headless mode without GUI support and additional dev tools:
```shell
docker pull ghcr.io/generalpepperoni/gemd-core:latest
docker run --rm -itd --network=host --name gemd ghcr.io/generalpepperoni/gemd-core:latest
```


## Usage

Let's run some simulation scripts, to make simulated E2 cart take a ride! 
```shell
docker exec -it gemd bash -lc 'rosrun gem_pure_pursuit_sim pure_pursuit_sim.py'
```

Now you can interact with GEMd `roscore`:
```shell
# For example: Run additional tools like rqt_plot (in case of GUI setup) 
docker exec -it gemd bash -lc 'rqt_plot /gem/metrics/ct_error'
```

Or run some quick custom [validation scripts](https://github.com/generalpepperoni/POLARIS_GEM_e2/blob/devel/polaris_gem_drivers_sim/gem_pure_pursuit_sim/scripts/crosstrack_error_validation.py):
```shell
# e.g. Calculate average Crosstrack error
docker exec -it gemd bash -lc 'rosrun gem_pure_pursuit_sim crosstrack_error_validation.py --persist --duration=5'

# Get CT error in real time
docker exec -it gemd bash -lc 'rostopic echo /gem/metrics/ct_error'
# Or get the last CT error from rostopic
docker exec -it gemd bash -lc 'rostopic echo -n 1 /gem/metrics/ct_error_avg_last 2>/dev/null | grep "^data:" | awk "{print \$NF}"'
```

Or directly access GEMd container shell:
```shell
docker exec -it gemd bash
```

## Installing and running on Kubernetes

GEMd can be deployed to `Kubernetes` cluster, using bundled [Helm Char(helm/Chart.yaml):
```shell
helm upgrade --install gemd ./helm \
    --create-namespace \
    --namespace gemd-dev \
    --set image.repository=ghcr.io/generalpepperoni/gemd-core \
    --set image.tag=latest \
    --atomic \
    --wait \
    --timeout 10m \
    --cleanup-on-fail
```

Get Pod name:
```shell
export GEMD_POD=$(kubectl get pods -n gemd-dev -l app=gemd-core -o jsonpath='{.items[0].metadata.name}' --field-selector=status.phase=Running)
```

Run simulation command in k8s pod:
```shell
kubectl exec -n gemd-dev $GEMD_POD -- bash -lc 'rosrun gem_pure_pursuit_sim pure_pursuit_sim.py'
kubectl exec -n gemd-dev $GEMD_POD -- bash -lc 'rosrun gem_pure_pursuit_sim crosstrack_error_validation.py --persist --duration=20'
```
Helm Chart has the rostopic-based `/opt/healthcheck.sh` scrip.
