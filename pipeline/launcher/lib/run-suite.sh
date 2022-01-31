#!/bin/bash

# this script distributes a run call to a suite-level or (extended) base container
# it is not used by pipeline-level containers, which call lib/execute.sh directly to run pipelines only
CONTAINER_ACTION=$1

# extend mdi-singularity-base (or another image) to add suites lacking container support
# this installation action runs in the base container and adds packages to the user's mdi/containers/library
if [ "$CONTAINER_ACTION" = "extend" ]; then
    exec Rscript -e "mdi::extend('$STATIC_MDI_DIR')"

# execute a pipeline
#   suite-level containers act the same as pipeline-level containers in this regard
#   (extended) base containers are not relevant to pipelines (empty containers never carry environments)
elif [ "$CONTAINER_ACTION" = "pipeline" ]; then
    if [ "$HAS_PIPELINES" != "true" ]; then 
        echo "container does not have pipelines installed"
        exit 1
    fi 
    exec bash ${LAUNCHER_DIR}/lib/execute.sh

# launch the apps server, setting a flag that is passed to run.R/run_server.R
#   suite-level containers use:
#     static, versioned framework and suites code provided by the container (and thus don't support live version switching)
#     active, bind-mounted data and sessions files
#   extended base containers:
#     provide R package libraries only, via .libPaths() set in run_server.R
#     otherwise, all code, data, and sessions file are active via bind-mount, like any server
elif [ "$CONTAINER_ACTION" = "apps" ]; then
    if [ "$HAS_APPS" != "true" ]; then 
        echo "container does not have apps installed"
        exit 1
    fi 
    export MDI_CONTAINER_TYPE=$2
    RUN_COMMAND=$3
    DATA_DIR=$4
    exec Rscript -e "mdi::$RUN_COMMAND('$ACTIVE_MDI_DIR', dataDir = '$DATA_DIR')"

# abort and report usage error
else
    echo "usage error: please run this container using an MDI command"
fi
