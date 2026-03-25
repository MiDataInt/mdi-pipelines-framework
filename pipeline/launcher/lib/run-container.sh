#!/bin/bash

# this script distributes a singularity run call to a suite-level container
CONTAINER_ACTION=$1

# execute a pipeline action configured by the launcher
if [ "$CONTAINER_ACTION" = "run_pipeline" ]; then
    if [ "$HAS_PIPELINES" != "true" ]; then 
        echo "container does not have any MDI pipelines installed"
        echo "is this an apps container?"
        exit 1
    fi 
    exec bash ${LAUNCHER_DIR}/lib/execute.sh

# launch the apps server, passing container metadata to run.R/run_server.R
#   provide R package libraries via .libPaths() set here and in run_server.R
#   bind-mount all code, data, and sessions files, to otherwise run like any MDI server
elif [ "$CONTAINER_ACTION" = "run_apps" ]; then
    if [ "$HAS_APPS" != "true" ]; then 
        echo "container does not have MDI apps installed"
        echo "is this a pipeline container?"
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

# otherwise pass all arguments to the container's static MDI installation directly
else
    if [ "$HAS_PIPELINES" = "true" ]; then 
        export MDI_DIR=${STATIC_MDI_DIR}
        exec ${STATIC_MDI_DIR}/mdi "$@"

    # abort and report usage error
    else
        echo "usage error: please run this apps container using an MDI command"
        exit 1
    fi
fi
