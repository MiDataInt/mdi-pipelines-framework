use strict;
use warnings;
use File::Path qw(make_path);

# main sub for executing a pipeline action

# working variables
use vars qw($pipelineName $pipelineSuite $pipelineDir $modulesDir
            @args $config $isSingleAction
            %longOptions %optionArrays $workflowScript $isNTasks
            $suitesDir %workingSuiteVersions);

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
    my $assembled = reportAssembledConfig($action, $conda, 1);
    
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
        manageTaskEnvironment($action, $cmd, $isDryRun, $assembled, $taskReport);
        copyTaskCodeSuites();
        executeTaskBash($action, $isDryRun, $isSingleTask, $assembled, $taskId, $conda);
    } 
}
sub getCmdHash {                # the name of this function, 'cmd', and the varnames it populates
    my $name = $_[0] or return; # is a legacy holdover from when 'actions' were called 'commands'
    $$config{actions}{$name};
} 

# parse the options and construct a call to a single pipeline task
# a task is a pipeline action applied to a given data set, with a single output folder
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
sub manageTaskEnvironment { # set all task environment variables (listed in tool suite pipeline README.md)
    my ($action, $cmd, $isDryRun, $assembled, $taskReport) = @_;

    # parse and create derivative paths and prefixes for this task
    $ENV{TASK_DIR}          = "$ENV{OUTPUT_DIR}/$ENV{DATA_NAME}"; # guaranteed unique per task by validateOptionArrays
    $ENV{DATA_FILE_PREFIX}  = "$ENV{TASK_DIR}/$ENV{DATA_NAME}"; 
    $ENV{PLOTS_DIR}         = "$ENV{TASK_DIR}/plots"; 
    $ENV{PLOT_PREFIX}       = "$ENV{PLOTS_DIR}/$ENV{DATA_NAME}"; 
    $ENV{SUITE_NAME}        = $pipelineSuite;
    $ENV{PIPELINE_NAME}     = $pipelineName; 
    $ENV{PIPELINE_ACTION}   = $action;
    $ENV{TASK_PIPELINE_DIR} = "$ENV{TASK_DIR}/$pipelineName"; 
    $ENV{TASK_ACTION_DIR}   = "$ENV{TASK_PIPELINE_DIR}/$action";
    $ENV{SUITES_DIR}        = "$ENV{TASK_ACTION_DIR}/suites";
    $ENV{SUITE_DIR}         = "$ENV{SUITES_DIR}/$pipelineSuite"; 
    $ENV{PIPELINE_DIR}      = "$ENV{SUITE_DIR}/pipelines/$pipelineName"; 
    $ENV{MODULES_DIR}       = "$ENV{SUITE_DIR}/shared/modules";

    # (re)initialize the log file for this task (always carries just the most recent execution)
    $ENV{LOGS_DIR}        = "$ENV{TASK_ACTION_DIR}/logs"; 
    $ENV{LOG_FILE_PREFIX} = "$ENV{LOGS_DIR}/$ENV{DATA_NAME}"; 
    $ENV{TASK_LOG_FILE}   = "$ENV{LOG_FILE_PREFIX}.$pipelineName.$action.task.log";
    if (!$isDryRun) {
        -d $ENV{LOGS_DIR} or make_path($ENV{LOGS_DIR});
        open my $outH, ">", $ENV{TASK_LOG_FILE} or throwError("could not open:\n    $ENV{TASK_LOG_FILE}\n$!");
        print $outH "$$assembled{report}$$taskReport";
        close $outH;
    }

    # set memory-related environment variables
    $ENV{RAM_PER_CPU_INT} = getIntRam($ENV{RAM_PER_CPU}); 
    $ENV{TOTAL_RAM_INT}   = $ENV{RAM_PER_CPU_INT} * $ENV{N_CPU};       
    $ENV{TOTAL_RAM}       = getStrRam($ENV{TOTAL_RAM_INT});

    # pass some options to snakemake
    $ENV{SN_DRY_RUN}  = $ENV{SN_DRY_RUN}  ? '--dry-run'  : "";
    $ENV{SN_FORCEALL} = $ENV{SN_FORCEALL} ? '--forceall' : "";

    # parse our script target
    $ENV{ACTION_DIR}    = $$cmd{module} ? "$ENV{MODULES_DIR}/$$cmd{module}[0]" : "$ENV{PIPELINE_DIR}/$action";
    $ENV{ACTION_SCRIPT} = $$cmd{script} || "Workflow.sh";
    $ENV{ACTION_SCRIPT} = "$ENV{ACTION_DIR}/$ENV{ACTION_SCRIPT}";
    $ENV{SCRIPT_DIR}    = "$ENV{ACTION_DIR}"; # set some legacy aliases  
    $ENV{SCRIPT_TARGET} = "$ENV{ACTION_SCRIPT}"; 

    # add any pipeline-specific environment variables as last step
    # thus can use any standard pipeline variables to construct new, pipeline-specific ones
    my $pipelineScript = "$pipelineDir/pipeline.pl";
    -f $pipelineScript and require $pipelineScript;     
}
sub copyTaskCodeSuites { # create a permanent, fixed working copy of all tool suite code required by this task
    sub copyCodeDir {
        my ($srcDir, $destDir) = @_;
        make_path($destDir);
        system("cp -fr $srcDir/* $destDir") and die "suite code copy failed: $!\n    $srcDir\n    $destDir\n";
    }
    foreach my $suiteDir(keys %workingSuiteVersions){
        my @parts = split("/", $suiteDir); 
        my $suiteName = $parts[$#parts];
        if($suiteName eq $pipelineSuite){ # this pipeline's suite copies the pipeline itself (all actions) and all shared modules
            copyCodeDir($pipelineDir, $ENV{PIPELINE_DIR});
            copyCodeDir($modulesDir,  $ENV{MODULES_DIR});
        } else { # external modules always come from definitive code suites
            my $modulesPath = "$suiteName/shared/modules";
            my $modulesDirSrc  = "$suitesDir/$modulesPath";
            my $modulesDirDest = "$ENV{SUITES_DIR}/$modulesPath";
            copyCodeDir($modulesDirSrc,  $ENV{modulesDirDest});
        }
    }
    -e $ENV{ACTION_SCRIPT} or throwError("pipeline configuration error\n". # from a pipeline action or shared module folder
                                         "missing script target:\n    $ENV{ACTION_SCRIPT}"); 
}
sub executeTaskBash {
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
source $ENV{ACTION_SCRIPT}
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
