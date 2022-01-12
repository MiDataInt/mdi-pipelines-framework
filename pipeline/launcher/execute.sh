#!/bin/bash

# this script is called to execute a pipeline

# acivate the conda environment
${CONDA_LOAD_COMMAND}
source ${CONDA_PROFILE_SCRIPT}
conda activate ${ENVIRONMENTS_DIR}/${CONDA_NAME}

# prepare the task workflow for execution
source ${WORKFLOW_SH}
if [ "${LAST_SUCCESSFUL_STEP}" != "" ]; then
    echo "rolling back to pipeline step ${LAST_SUCCESSFUL_STEP}"
    echo
    resetWorkflowStatus
fi
showWorkflowStatus

# execute the task, i.e., apply the pipeline action to the current data set
source ${ACTION_SCRIPT}

# as needed, create a Stage 2 data package from this task's output
perl ${WORKFLOW_DIR}/package.pl
