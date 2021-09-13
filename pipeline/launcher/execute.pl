use strict;
use warnings;

# main sub for executing a command

# working variables
use vars qw($mainDir $pipelineName $pipelineDir $modulesDir
            @args $config $isSingleCommand
            %longOptions %optionArrays $workflowScript $isNTasks);

# parse the options and construct a call to a single command
sub executeCommand {
    my ($actionCommand) = @_;
    
    # set the commands list and working command
    my $cmd = getCmdHash($actionCommand);
    !$cmd and showCommandsHelp("unknown command: $actionCommand", 1);
    
    # process the options for the command and request
    my $configYml = parseAllOptions($actionCommand);
    parseAllDependencies($actionCommand);
    my $conda = getCondaPaths($configYml);

    # collect options and dependency feeback, for log files and streams
    my $assembled = reportAssembledConfig($actionCommand, $conda);
    
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
                            "'$ENV{PIPELINE_NAME} $actionCommand' requires $requiredRamStr");
        }        
    }

    # do the requested work by task id
    $optionArrays{quiet}[0] or print $$assembled{report};
    my $isDryRun = $$assembled{taskOptions}[0]{'dry-run'};
    foreach my $i(@workingTaskIs){    
        my ($taskId, $taskReport) = processCommandTask($assembled, $i, $requestedTaskId, @workingTaskIds);
        manageCommandEnvironment($actionCommand, $cmd, $isDryRun, $assembled, $taskReport);
        executeBashCommand($actionCommand, $isDryRun, $isSingleTask, $assembled, $taskId, $conda);
    } 
}
sub getCmdHash {
    my $name = $_[0] or return;
    $$config{commands}{$name};
} 
sub processCommandTask {
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
sub manageCommandEnvironment {
    my ($actionCommand, $cmd, $isDryRun, $assembled, $taskReport) = @_;
    
        # parse and create universal derivative paths
        $ENV{DATA_NAME_DIR}    = "$ENV{OUTPUT_DIR}/$ENV{DATA_NAME}"; # guaranteed unique per task by validateOptionArrays
        $ENV{DATA_FILE_PREFIX} = "$ENV{DATA_NAME_DIR}/$ENV{DATA_NAME}";
        $ENV{DATA_GENOME_PREFIX} = $ENV{GENOME} ? "$ENV{DATA_FILE_PREFIX}.$ENV{GENOME}" : "";
        $ENV{LOGS_DIR}         = "$ENV{DATA_NAME_DIR}/$ENV{PIPELINE_NAME}_logs";
        $ENV{LOG_FILE_PREFIX}  = "$ENV{LOGS_DIR}/$ENV{DATA_NAME}";
        $ENV{TASK_LOG_FILE}    = "$ENV{LOG_FILE_PREFIX}.$actionCommand.task.log";
        $ENV{PLOTS_DIR}        = "$ENV{DATA_NAME_DIR}/plots";
        $ENV{PLOT_PREFIX}      = $ENV{GENOME} ? "$ENV{PLOTS_DIR}/$ENV{DATA_NAME}.$ENV{GENOME}" : "$ENV{PLOTS_DIR}/$ENV{DATA_NAME}";
        if (!$isDryRun) {
            -d $ENV{DATA_NAME_DIR} or mkdir $ENV{DATA_NAME_DIR};
            -d $ENV{LOGS_DIR} or mkdir $ENV{LOGS_DIR};
            
            # (re)initialize the log file for this command task (always carries just the most recent execution)
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
        $ENV{SCRIPT_DIR} = $$cmd{module} ? "$modulesDir/$$cmd{module}[0]" : "$pipelineDir/$actionCommand";
        $ENV{SCRIPT_TARGET} = $$cmd{script} || "Workflow.sh";
        $ENV{SCRIPT_TARGET} = "$ENV{SCRIPT_DIR}/$ENV{SCRIPT_TARGET}";
        -e $ENV{SCRIPT_TARGET} or throwError("pipeline configuration error\n".
                                             "missing script target:\n    $ENV{SCRIPT_TARGET}");
        $ENV{COMMAND_DIR} = $ENV{SCRIPT_DIR};
        $ENV{COMMAND_TARGET} = $ENV{SCRIPT_TARGET};
        
        # add any pipeline-specific environment variables as last step
        exists &setDerivativeVariables and setDerivativeVariables($actionCommand);        
}
sub executeBashCommand {
    my ($actionCommand, $isDryRun, $isSingleTask, $assembled, $taskId, $conda) = @_;

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
        -d $$conda{dir} or throwError("missing conda environment for command '$actionCommand'\n".
                                      "please run '$ENV{PIPELINE_NAME} conda --create' before running the pipeline");

        # single commands or tasks replace this process and never return
        $isSingleCommand and $isSingleTask and exec $bash;
        
        # multiple commands or tasks require that we stay alive to run the next one 
        system($bash) and throwError("command '$actionCommand' task #$taskId had non-zero exit status\n".
                                     "no more commands or tasks will be executed");
    }   
}

1;

