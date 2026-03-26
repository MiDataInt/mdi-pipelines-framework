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

    # options as provided by mdi-pipelines-framework/job_manager/lib/commands/server.pl::launchServerContainer()
    #     run_apps $serverCmd $dataDir $port
    RUN_COMMAND=$2
    DATA_DIR=$3
    SHINY_PORT=$4

    # launch the server, telling R where to find the mdi package
    exec Rscript -e ".libPaths('$STATIC_R_LIBRARY_SHORT'); mdi::$RUN_COMMAND('$STATIC_MDI_DIR', dataDir = '$DATA_DIR', port = $SHINY_PORT)"

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
