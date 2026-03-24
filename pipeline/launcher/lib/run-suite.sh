#!/bin/bash

# this script distributes a run call to a suite-level container
# it is not used by pipeline-level containers, which call lib/execute.sh directly to run pipelines only
CONTAINER_ACTION=$1

# execute a pipeline
#   suite-level containers act the same as pipeline-level containers in this regard
#   this is a legacy usage from when suite-level containers mixed pipeline and apps support (they no longer do)
if [ "$CONTAINER_ACTION" = "pipeline" ]; then
    if [ "$HAS_PIPELINES" != "true" ]; then 
        echo "container does not have pipelines installed"
        exit 1
    fi 
    exec bash ${LAUNCHER_DIR}/lib/execute.sh

# launch the apps server, passing container metadata to run.R/run_server.R
#   provide R package libraries via .libPaths() set here and in run_server.R
#   bind-mount all code, data, and sessions files, to otherwise run like any MDI server
elif [ "$CONTAINER_ACTION" = "apps" ]; then
    if [ "$HAS_APPS" != "true" ]; then 
        echo "container does not have apps installed"
        exit 1
    fi 

    # ensure that the MDI's R lib is used to load the mdi package
    # otherwise it can get prepended by an outdated lib from system R_LIBS_USER
    SET_LIB_PATHS=".libPaths('$MDI_SYSTEM_R_LIBRARY')"

    # launch the server
    export MDI_CONTAINER_TYPE=$2
    RUN_COMMAND=$3
    DATA_DIR=$4
    SHINY_PORT=$5
    if [ "$SHINY_PORT" = "" ]; then SHINY_PORT=3838; fi
    exec Rscript -e "$SET_LIB_PATHS; mdi::$RUN_COMMAND('$ACTIVE_MDI_DIR', dataDir = '$DATA_DIR', port = $SHINY_PORT)"

# abort and report usage error
else
    echo "usage error: please run this container using an MDI command"
fi
