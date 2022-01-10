# workflow.sh has utility functions for managing a bash-based workflow script

#--------------------------------------------------------------------
# place some internal utilities into PATH
#--------------------------------------------------------------------
export PATH=$MODULES_DIR/utilities:$PATH

#--------------------------------------------------------------------
# get and set the last successfully completed step in a multi-step serial workflow
#--------------------------------------------------------------------
function setStatusFile { # construct a rule-based status file name
    if [ "$OUTPUT_DIR" = "" ]; then
        echo "missing variable: OUTPUT_DIR"
        exit 1
    fi
    if [ ! -d "$OUTPUT_DIR" ]; then # OUTPUT_DIR must exist, it will not be created
        echo "directory does not exist: $OUTPUT_DIR"
        exit 1
    fi
    if [ "$PIPELINE_NAME" = "" ]; then
        echo "missing variable: PIPELINE_NAME"
        exit 1
    fi
    if [ "$PIPELINE_ACTION" = "" ]; then
        echo "missing variable: PIPELINE_ACTION"
        exit 1
    fi 
    if [ "$DATA_NAME" = "" ]; then
        echo "missing variable: DATA_NAME"
        exit 1
    fi
    if [ "$TASK_PIPELINE_DIR" = "" ]; then
        echo "missing variable: TASK_PIPELINE_DIR"
        exit 1
    fi
    if [ "$TASK_ACTION_DIR" = "" ]; then
        echo "missing variable: TASK_ACTION_DIR"
        exit 1
    fi
    if [ ! -d "$TASK_ACTION_DIR" ]; then mkdir -p $TASK_ACTION_DIR; fi # a direct child of TASK_PIPELINE_DIR, under OUTPUT_DIR
    STATUS_FILE=$TASK_PIPELINE_DIR/$DATA_NAME.$PIPELINE_NAME.status # a pipeline level file, includes all steps for all actions
    if [ ! -e "$STATUS_FILE" ]; then touch $STATUS_FILE; fi  
}
function getWorkflowStatus {
    setStatusFile
    LAST_SUCCESSFUL_STEP=`awk '$1=="'$PIPELINE_ACTION'"' $STATUS_FILE | tail -n1 | cut -f2`
    if [ "$LAST_SUCCESSFUL_STEP" = "" ]; then LAST_SUCCESSFUL_STEP=0; fi
}
function setWorkflowStatus {
    setStatusFile
    STEP_NUMBER=$1
    STEP_NAME=$2
    STEP_SCRIPT=$3
    DATE=`date`
    echo -e "$PIPELINE_ACTION\t$STEP_NUMBER\t$STEP_NAME\t$DATE" >> $STATUS_FILE
}
function resetWorkflowStatus { # override any prior job outcomes and force a new status
    setStatusFile
    if [ "$LAST_SUCCESSFUL_STEP" != "" ]; then
        awk '$1!="'$PIPELINE_ACTION'"||$2<='$LAST_SUCCESSFUL_STEP $STATUS_FILE >> $STATUS_FILE.tmp
        mv -f $STATUS_FILE.tmp $STATUS_FILE
    fi
}
function showWorkflowStatus {
    setStatusFile
    STATUS_LINE_LENGTH=`cat $STATUS_FILE | wc -l`
    if [[ "$STATUS_LINE_LENGTH" -gt "0" && "$QUIET" = "" ]]; then
        echo -e "ACTION\tSTEP#\tSTEP\tDATE"
        cat $STATUS_FILE
        echo
    fi
}
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# execute a pipeline step by sourcing its script, if not already successfully completed
#--------------------------------------------------------------------
function runWorkflowStep {   
    STEP_NUMBER=$1
    STEP_NAME=$2
    STEP_SCRIPT=$3
    getWorkflowStatus    
    if [ "$LAST_SUCCESSFUL_STEP" -lt "$STEP_NUMBER" ]; then
        if [[ "$STEP_SCRIPT" == /* ]]; then
            TARGET_SCRIPT=$STEP_SCRIPT # an absolute script path was provided
        else
            TARGET_SCRIPT=$ACTION_DIR/$STEP_SCRIPT # path interpreted relative to current action step
        fi
        source $TARGET_SCRIPT # NB: script is responsible for calling checkPipe to validate execution success
        setWorkflowStatus $STEP_NUMBER $STEP_NAME $STEP_SCRIPT
    else
        echo "already succeeded: $PIPELINE_ACTION"", step $STEP_NUMBER, $STEP_NAME, $STEP_SCRIPT"
        echo
    fi    
}
#--------------------------------------------------------------------
# alternatively let the caller handle the execution, just communicate step state
# e.g., to have another flow controller, like snakemake, handle a step's execution
#--------------------------------------------------------------------
function checkWorkflowStep {
    STEP_NUMBER=$1
    STEP_NAME=$2
    STEP_SCRIPT=$3
    getWorkflowStatus    
    if [ "$LAST_SUCCESSFUL_STEP" -lt "$STEP_NUMBER" ]; then
        STEP_SATISFIED=""    
    else
        echo "already succeeded: $PIPELINE_ACTION"", step $STEP_NUMBER, $STEP_NAME"
        echo
        STEP_SATISFIED="TRUE"        
    fi    
}
function finishWorkflowStep {
    setWorkflowStatus $STEP_NUMBER $STEP_NAME $STEP_SCRIPT    
}
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# ensure that all commands in a pipe had exit_status=0
# use after a bash command or piped stream to force pipeline to fail if command fails
#--------------------------------------------------------------------
function checkPipe {  
    local PSS=${PIPESTATUS[*]}
    for PS in $PSS; do
       if [[ ( $PS > 0 ) ]]; then
           echo "pipe error: [$PSS]"
           exit 99
       fi;
    done
}
#--------------------------------------------------------------------

#--------------------------------------------------------------------
# ensure a job will have data to work on
#--------------------------------------------------------------------
function checkForData { # ensure that a data stream will have at least one line of data
    local COMMAND="$1"
    if [ "$COMMAND" = "" ]; then
        echo "checkForData error: system command not provided"
        exit 100
    fi
    local LINE_1="`$COMMAND | head -n1`"
    if [ "$LINE_1" = "" ]; then
        echo "no data; exiting quietly"
        exit 0
    fi
}
function waitForFile {  # wait for a file to appear on the file system; default timeout=60 seconds
    local FILE="$1"
    local TIME_OUT="$2"
    if [ "$FILE" = "" ]; then
        echo "waitForFile error: file not provided"
        exit 100
    fi
    if [ "$TIME_OUT" = "" ]; then
        local TIME_OUT=60
    fi
    local ELAPSED=0
    while [ ! -s $FILE ]
    do
        sleep 2;
        let "ELAPSED += 2"
        if [ "$ELAPSED" -gt "$TIME_OUT" ]; then
            echo "waitForFile error: $FILE not found after $TIME_OUT seconds"
            exit 100
        fi
    done
}
function checkFileExists {  # verify non-empty file, or first of glob if called as checkFileExists $GLOB
    local FILE="$1"
    if [ "$FILE" = "" ]; then
        echo "checkFileExists error: file not provided"
        exit 100
    fi
    if [ ! -s "$FILE" ]; then
        echo "file empty or not found on node "`hostname`
        echo $FILE
        exit 100
    fi
}
#--------------------------------------------------------------------
