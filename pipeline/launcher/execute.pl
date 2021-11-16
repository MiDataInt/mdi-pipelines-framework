use strict;
use warnings;

# main sub for executing a pipeline action

# working variables
use vars qw($pipelineName $pipelineDir $modulesDir
            @args $config $isSingleAction
            %longOptions %optionArrays $workflowScript $isNTasks);

# parse the options and construct a call to a single pipeline action
sub executeAction {
    my ($action) = @_;
    
    # set the actions list and working action
    my $cmd = getCmdHash($action);
    !$cmd and showActionsHelp("unknown action: $action", 1);

    # process the options for the action and request
    my $configYml = parseAllOptions($action);
    parseAllDependencies($action);
    my $conda = getCondaPaths($configYml);

    # collect options and dependency feeback, for log files and streams
    my $assembled = reportAssembledConfig($action, $conda);
    
    # get the list of task id(s) we are being asked to run (or check)
    my $requestedTaskId = $$assembled{taskOptions}[0]{'task-id'};
    my $nTasks = @{$$assembled{taskOptions}};
    $requestedTaskId < 0 and throwError("bad task-id: $requestedTaskId");
    $requestedTaskId > $nTasks and throwError("bad task-id: $requestedTaskId\nnot that many tasks");
    my @workingTaskIds = $requestedTaskId ? $requestedTaskId : (1..$nTasks);
    my @workingTaskIs = map { $_ - 1 } @workingTaskIds; # 0-indexed, unlike taskIds
    my $isSingleTask = @workingTaskIds == 1;    

    # check memory requirements for all requested task id(s)
    my $requiredRamStr = $$cmd{resources}{required}{'total-ram'}[0];
    my $requiredRamInt = getIntRam($requiredRamStr);
    foreach my $i(@workingTaskIs){
        my $ramPerCpu = getIntRam($$assembled{taskOptions}[$i]{'ram-per-cpu'});        
        my $totalRamInt = $ramPerCpu * $$assembled{taskOptions}[$i]{'n-cpu'};
        if($totalRamInt < $requiredRamInt){
            my $taskId = $i + 1;
            showOptionsHelp("insufficent net RAM for task #$taskId\n".
                            "'$ENV{PIPELINE_NAME} $action' requires $requiredRamStr");
        }        
    }

    # do the requested work by task id
    $optionArrays{quiet}[0] or print $$assembled{report};
    my $isDryRun = $$assembled{taskOptions}[0]{'dry-run'};
    foreach my $i(@workingTaskIs){    
        my ($taskId, $taskReport) = processActionTask($assembled, $i, $requestedTaskId, @workingTaskIds);
        manageActionEnvironment($action, $cmd, $isDryRun, $assembled, $taskReport);
        executeActionBash($action, $isDryRun, $isSingleTask, $assembled, $taskId, $conda);
    } 
}
sub getCmdHash {
    my $name = $_[0] or return;
    $$config{actions}{$name};
} 
sub processActionTask {
    my ($assembled, $i, $requestedTaskId, @workingTaskIds) = @_;
    
    # get and set this task
    my $optionValues = $$assembled{taskOptions}[$i];        
    my $taskId = $i + 1;
    $$optionValues{'task-id'} = $taskId;
    
    # if relevant, report this task's option values to log stream
    my $taskReport = "";
    if ($requestedTaskId or @workingTaskIds > 1) {
        $taskReport .= "---\n";
        $taskReport .= "task:\n";
        $taskReport .= "    task-id: $taskId\n";
        foreach my $longOption(keys %optionArrays){
            my $nValues = scalar( @{$optionArrays{$longOption}} );
            $nValues > 1 and $taskReport .= "    $longOption: $$optionValues{$longOption}\n"; 
        }
        $taskReport .= "...\n\n";
    }
    $optionArrays{quiet}[0] or print $taskReport;        

    # load environment variables with provided values for use by running pipelines
    foreach my $optionLong(keys %$optionValues){
        setEnvVariable($optionLong, $$optionValues{$optionLong}); 
    }
    ($taskId, \$taskReport);
}
sub manageActionEnvironment {
    my ($action, $cmd, $isDryRun, $assembled, $taskReport) = @_;
    
        # parse and create universal derivative paths
        $ENV{DATA_NAME_DIR}    = "$ENV{OUTPUT_DIR}/$ENV{DATA_NAME}"; # guaranteed unique per task by validateOptionArrays
        $ENV{DATA_FILE_PREFIX} = "$ENV{DATA_NAME_DIR}/$ENV{DATA_NAME}";
        $ENV{DATA_GENOME_PREFIX} = $ENV{GENOME} ? "$ENV{DATA_FILE_PREFIX}.$ENV{GENOME}" : "";
        $ENV{LOGS_DIR}         = "$ENV{DATA_NAME_DIR}/$ENV{PIPELINE_NAME}_logs";
        $ENV{LOG_FILE_PREFIX}  = "$ENV{LOGS_DIR}/$ENV{DATA_NAME}";
        $ENV{TASK_LOG_FILE}    = "$ENV{LOG_FILE_PREFIX}.$action.task.log";
        $ENV{PLOTS_DIR}        = "$ENV{DATA_NAME_DIR}/plots";
        $ENV{PLOT_PREFIX}      = $ENV{GENOME} ? "$ENV{PLOTS_DIR}/$ENV{DATA_NAME}.$ENV{GENOME}" : "$ENV{PLOTS_DIR}/$ENV{DATA_NAME}";
        if (!$isDryRun) {
            -d $ENV{DATA_NAME_DIR} or mkdir $ENV{DATA_NAME_DIR};
            -d $ENV{LOGS_DIR} or mkdir $ENV{LOGS_DIR};
            
            # (re)initialize the log file for this task (always carries just the most recent execution)
            open my $outH, ">", $ENV{TASK_LOG_FILE} or throwError("could not open:\n    $ENV{TASK_LOG_FILE}\n$!");
            print $outH "$$assembled{report}$$taskReport";
            close $outH;
        }

        # set memory-related environment variables
        $ENV{RAM_PER_CPU_INT} = getIntRam($ENV{RAM_PER_CPU}); 
        $ENV{TOTAL_RAM_INT} = $ENV{RAM_PER_CPU_INT} * $ENV{N_CPU};       
        $ENV{TOTAL_RAM} = getStrRam($ENV{TOTAL_RAM_INT});

        # pass some options to snakemake
        $ENV{SN_DRY_RUN}  = $ENV{SN_DRY_RUN}  ? '--dry-run'  : "";
        $ENV{SN_FORCEALL} = $ENV{SN_FORCEALL} ? '--forceall' : "";

        # parse our script target
        $ENV{SCRIPT_DIR} = $$cmd{module} ? "$modulesDir/$$cmd{module}[0]" : "$pipelineDir/$action";
        $ENV{SCRIPT_TARGET} = $$cmd{script} || "Workflow.sh";
        $ENV{SCRIPT_TARGET} = "$ENV{SCRIPT_DIR}/$ENV{SCRIPT_TARGET}";
        -e $ENV{SCRIPT_TARGET} or throwError("pipeline configuration error\n".
                                             "missing script target:\n    $ENV{SCRIPT_TARGET}");
        $ENV{ACTION_DIR} = $ENV{SCRIPT_DIR};
        $ENV{ACTION_TARGET} = $ENV{SCRIPT_TARGET};
        
        # add any pipeline-specific environment variables as last step
        my $pipelineScript = "$pipelineDir/pipeline.pl";
        -f $pipelineScript and require $pipelineScript;     
}
sub executeActionBash {
    my ($action, $isDryRun, $isSingleTask, $assembled, $taskId, $conda) = @_;

    # parse our bash command that sets up the conda evironment
    my $rollback = $$assembled{taskOptions}[0]{rollback};
    $rollback = $rollback eq 'null' ? "" :
"echo
echo \"rolling back to pipeline step $rollback\"
echo
export LAST_SUCCESSFUL_STEP=$rollback
resetWorkflowStatus";
    my $bash =
"bash -c '
$$conda{loadCommand}
source $$conda{profileScript}
conda activate $$conda{dir}
source $workflowScript
$rollback
showWorkflowStatus
source $ENV{SCRIPT_TARGET}
perl $ENV{WORKFLOW_DIR}/package.pl
'";
    
    # do the work
    if (!$isDryRun) {

        # validate conda environment
        -d $$conda{dir} or throwError("missing conda environment for action '$action'\n".
                                      "please run 'mdi $ENV{PIPELINE_NAME} conda --create' before launching the pipeline");

        # single actions or tasks replace this process and never return
        $isSingleAction and $isSingleTask and exec $bash;
        
        # multiple actions or tasks require that we stay alive to run the next one 
        system($bash) and throwError("action '$action' task #$taskId had non-zero exit status\n".
                                     "no more actions or tasks will be executed");
    }   
}

1;
