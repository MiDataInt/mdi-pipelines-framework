#!/bin/bash

# this script is called to open a shell in a pipeline's environment
# useful for developer's to explore command options

# acivate the conda environment
${CONDA_LOAD_COMMAND}
source ${CONDA_PROFILE_SCRIPT}
conda activate ${ENVIRONMENTS_DIR}/${CONDA_NAME}
