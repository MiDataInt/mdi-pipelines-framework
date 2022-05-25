#--------------------------------------------------------------------
# these functions are automatically called by every target script
#--------------------------------------------------------------------
function checkPredecessors {  # check whether predecessors timed out
    if [ "$SCHEDULER_TYPE" = "SGE" ]; then  # predecessor time-out checking only required for SGE
        if [ "$JOB_PREDECESSORS" != "" ]; then 
            sleep 2  # give the prior job's log file a moment to finish being written    
            IFS=":" read -a JOB_IDS <<< "$JOB_PREDECESSORS"  # read the array of predecessor jobIDs
            for JOB_ID in "${JOB_IDS[@]}"
            do
            	local FAILED="`grep -L 'q: exit_status:' $SCHEDULER_LOG_DIR/*.o$JOB_ID* 2>/dev/null`"  # returns filenames that failed to record an exit status, i.e. timed out
            	if [ "$FAILED" != "" ]; then 
            	    echo "predecessor job $JOB_ID failed to report an exit status (it probably timed out)"
            	    exit 100
            	fi
            done  
        fi
    fi
}
function getTaskID {  # $TASK_ID is not set if this is not an array job
    if [[ "$PBS_ARRAYID" = "" && "$SGE_TASK_ID" = "" && "$SLURM_ARRAY_TASK_ID" = "" ]]; then
        TASK_NUMBER=1
        TASK_ID=""     
    elif [ ${PBS_ARRAYID+1} ]; then
        TASK_NUMBER=$PBS_ARRAYID
        TASK_ID="--task-id $PBS_ARRAYID"
    elif [ ${SGE_TASK_ID+1} ]; then
        TASK_NUMBER=$SGE_TASK_ID
        TASK_ID="--task-id $SGE_TASK_ID"
    elif [ ${SLURM_ARRAY_TASK_ID+1} ]; then
        TASK_NUMBER=$SLURM_ARRAY_TASK_ID
        TASK_ID="--task-id $SLURM_ARRAY_TASK_ID"
    fi
}
#--------------------------------------------------------------------
