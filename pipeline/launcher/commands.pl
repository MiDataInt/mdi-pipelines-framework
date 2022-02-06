use strict;
use warnings;

# subs for handling universal pipeline commands
# most terminate execution or never return

# working variables
use vars qw($pipeline $pipelineName $pipelineSuiteDir $launcherDir $mdiDir
            @args $config %longOptions $workflowScript %workingSuiteVersions);

# switch for acting on restricted commands
sub doRestrictedCommand {
    my ($target) = @_;
    my %restricted = (

        # commands advertised to users
        template => \&runTemplate,
        conda    => \&runConda,
        build    => \&runBuild,
        shell    => \&runShell,
        status   => \&runStatus,
        rollback => \&runRollback,

        # commands for developers or MDI-internal use
        options         => \&runOptions, 
        optionsTable    => \&runOptionsTable,
        valuesYaml      => \&runValuesYaml,
        checkContainer  => \&checkContainer,
        buildSuite      => \&buildSuite
    );
    $restricted{$target} and &{$restricted{$target}}();
}

#------------------------------------------------------------------------------
# return a template for data-file.yml for the user to modify
#------------------------------------------------------------------------------
sub runTemplate {
    
    # special handling of command line option flags
    my %options;
    my $help = "help";
    my $allOptions  = "all-options";
    my $addComments = "add-comments";
    foreach my $arg(@args){
        ($arg eq '-h' or $arg eq "--$help") and $options{$help}  = 1;        
        ($arg eq '-a' or $arg eq "--$allOptions")  and $options{$allOptions}  = 1;        
        ($arg eq '-c' or $arg eq "--$addComments") and $options{$addComments} = 1;
    }
    
    # if requested, show custom action help
    if($options{$help}){
        my $desc = getTemplateValue($$config{actions}{template}{description});
        my $pname = $$config{pipeline}{name}[0];
        print "\n$pname template: $desc\n";
        print  "\nusage: mdi $pname template [-a/--$allOptions] [-c/--$addComments] [-h/--help]\n";
        print  "\n    -a/--$allOptions    include all possible options [only include options needing values]";
        print  "\n    -c/--$addComments   add instructional comments for new users [comments omitted]";
        print "\n\n";
        releaseMdiGitLock(0);
    }
    
    # print the template to STDOUT
    writeDataFileTemplate($options{$allOptions}, $options{$addComments});
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# create or list the conda environment(s) required by the pipeline
#------------------------------------------------------------------------------
sub runConda {
    
    # see if user provided server.yml
    my $defaultServerYml = Cwd::abs_path("$mdiDir/config/stage1-pipelines.yml");
    my @newArgs = ($args[0] and $args[$#args] =~ m/\.yml$/) ? (pop @args) : ();
    
    # special handling of command line option flags
    my %options;
    my $help    = "help";
    my $list    = "list";
    my $create  = "create";
    my $force   = "force";
    my $noMamba = "no-mamba";
    foreach my $arg(@args){
        ($arg eq '-h' or $arg eq "--$help")    and $options{$help}    = 1;        
        ($arg eq '-l' or $arg eq "--$list")    and $options{$list}    = 1;        
        ($arg eq '-c' or $arg eq "--$create")  and $options{$create}  = 1;
        ($arg eq '-f' or $arg eq "--$force")   and $options{$force}   = 1;
        ($arg eq '-M' or $arg eq "--$noMamba") and $options{$noMamba} = 1;
    }
    (!$options{$list} and !$options{$create}) and $options{$help}  = 1;     
    my $error = ($options{$list} and $options{$create}) ?
                "\noptions '--$list' and '--$create' are mutually exclusive\n" : "";
                
    # if requested, show custom action help
    my $pname = $$config{pipeline}{name}[0];
    if($options{$help} or $error){
        my $usage;
        my $desc = getTemplateValue($$config{actions}{conda}{description});
        $usage .= "\n$pname conda: $desc\n";
        $usage .=  "\nusage: mdi $pname conda [options]\n";
        $usage .=  "\n    -l/--$list      show the yml config file for each pipeline action";
        $usage .=  "\n    -c/--$create    if needed, create/update the required conda environments";
        $usage .=  "\n    -f/--$force     do not prompt for permission to create/update environments"; 
        $usage .=  "\n    -M/--$noMamba  do not use Mamba, only use Conda to create environments";   
        $error and throwError($error.$usage);
        print "$usage\n\n";
        releaseMdiGitLock(0);
    }
    
    # list or create conda environments in action order
    @args = @newArgs;
    showCreateCondaEnvironments($options{$create}, $options{$force}, $options{$noMamba});
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# build a Singularity image and post to a registry (for suite developers)
#------------------------------------------------------------------------------
sub runBuild { 

    # command has limited options, collect them now
    # NOTE: as always, --version was already handled by launcher.pl: setPipelineSuiteVersion()
    my $help    = "help";
    my $version = "version";
    my $force   = "force";
    my $sandbox = "sandbox";
    my %options;   
    $args[0] or $args[0] = ""; 
    ($args[0] eq '-h' or $args[0] eq "--$help")    and $options{$help}    = 1;
    ($args[0] eq '-f' or $args[0] eq "--$force")   and $options{$force}   = 1;
    ($args[0] eq '-s' or $args[0] eq "--$sandbox") and $options{$sandbox} = 1;        
                
    # if requested, show custom action help
    my $pname = $$config{pipeline}{name}[0];
    if($options{$help}){
        my $usage;
        my $desc = getTemplateValue($$config{actions}{build}{description});
        $usage .= "\n$pname build: $desc\n";
        $usage .=  "\nusage: mdi $pname build [options]\n";  
        $usage .=  "\n    -h/--$help     show this help";    
        $usage .=  "\n    -v/--$version  the suite version to build from, as a git release tag or branch [latest]";
        $usage .=  "\n    -f/--$force    overwrite existing container images";  
        $usage .=  "\n    -s/--$sandbox  run singularity with the --sandbox option set"; 
        print "$usage\n\n";
        releaseMdiGitLock(0);
    }
    
    # call Singularity build action
    buildSingularity($options{$sandbox} ? "--sandbox" : "", $options{$force} ? "--force" : "");
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# open a command shell in a pipeline's runtime environment, either via conda or Singularity
#------------------------------------------------------------------------------
sub runShell {

    # command has limited options, collect --help first
    my $help    = "help";
    my $action  = "action";    
    my $runtime = "runtime";
    my %options;   
    $args[0] or $args[0] = ""; 
    ($args[0] eq '-h' or $args[0] eq "--$help") and $options{$help} = 1;

    # if requested, show custom action help
    if($options{$help}){
        my $usage;
        my $pname = $$config{pipeline}{name}[0];   
        my $desc = getTemplateValue($$config{actions}{shell}{description});
        $usage .= "\n$pname shell: $desc\n";
        $usage .=  "\nusage: mdi $pname shell [options]\n";  
        $usage .=  "\n    -h/--$help     show this help"; 
        $usage .=  "\n    -a/--$action   the pipeline action whose conda environment will be activated in the shell [do]";           
        $usage .=  "\n    -m/--$runtime  execution environment: one of direct, container, or auto (container if supported) [auto]";
        print "$usage\n\n";
        releaseMdiGitLock(0);
    }

    # collect and set the runtime options
    $args[2] or $args[2] = ""; 
    foreach my $i(0, 2){
        ($args[$i] eq '-a' or $args[$i] eq "--$action")  and $options{$action}  = $args[$i + 1];        
        ($args[$i] eq '-m' or $args[$i] eq "--$runtime") and $options{$runtime} = $args[$i + 1];
    }
    setRuntimeEnvVars($options{$runtime});

    # collect and set the pipeline action options
    my $defaultAction = $$config{actions}{do} ? "do" : "";
    $action = $options{$action} || $defaultAction;
    $action or throwError("option '--action' is required to launch a shell");
    my $cmd = getCmdHash($action);
    !$cmd and showActionsHelp("unknown action: $action", 1);        
    my $configYml = assembleCompositeConfig($cmd, $action);
    parseAllDependencies($action);
    my $conda = getCondaPaths($configYml, $action);

    # set the shell command based on runtime mode
    my $shellCommand;
    if($ENV{IS_CONTAINER}){
        my $uris = getContainerUris($ENV{CONTAINER_MAJOR_MINOR}, $ENV{CONTAINER_LEVEL} eq 'suite');
        my $singularity = "$ENV{SINGULARITY_LOAD_COMMAND}; singularity";
        pullPipelineContainer($uris, $singularity);
        my $script = "source \${CONDA_PROFILE_SCRIPT}; conda activate \${ENVIRONMENTS_DIR}/$$conda{name}; exec bash";
        $shellCommand = "$singularity exec $$uris{imageFile} bash -c '$script'"; # implicitly binds $PWD
    } else {
        -d $$conda{dir} or throwError(
            "missing conda environment for action '$action'\n".
            "please run 'mdi $pipelineName conda --create' before opening a direct shell"
        );  
        my $rcFile = glob("~/.mdi.rcfile");
        my $script = "$$conda{loadCommand}; source $$conda{profileScript}; conda activate $$conda{dir}; rm -f $rcFile\n";
	    open my $rcH, ">", $rcFile or throwError("could not write to $rcFile: $!");
	    print $rcH $script; # --rcfile configures environment before passing interactive shell to user; the file deletes itself
	    close $rcH;
	    $shellCommand = "bash --rcfile $rcFile";
    }

    # launch the shell
    releaseMdiGitLock();
    exec $shellCommand;
}

#------------------------------------------------------------------------------
# report on the current job completion status of the pipeline for a specific data directory
#------------------------------------------------------------------------------
sub runStatus {
    
    # check for a proper request
    my ($subjectAction, $error);
    ($subjectAction, @args) = @args;
    $subjectAction or $error .= "missing action\n";
    my $cmd = getCmdHash($subjectAction); 
    if(!$cmd){
        $subjectAction and $error .= "unkown action: $subjectAction\n";
        throwError(
            $error.
            "usage: mdi $$config{pipeline}{name}[0] status <action> [data.yml] [OPTIONS]"
        )
    }
    
    # get and check options
    parseAllOptions('status', $subjectAction);
    checkRestrictedTask($subjectAction);
    
    # do the work
    print "\n";
    releaseMdiGitLock();
    exec "bash -c 'source $workflowScript; showWorkflowStatus'";  
}

#------------------------------------------------------------------------------
# clear the job status for a specific data directory to force jobs to start anew
#------------------------------------------------------------------------------
sub runRollback {
    
    # check for a proper request
    my ($subjectAction, $statusLevel, $error);
    ($subjectAction, $statusLevel, @args) = @args;
    $subjectAction or $error .= "missing action\n";
    my $cmd = getCmdHash($subjectAction); 
    if(!$cmd or !defined $statusLevel){
        !$cmd and $subjectAction and $error .= "unkown action: $subjectAction\n";
        defined $statusLevel or $error .= "missing status level\n";
        throwError(
            $error.
            "usage: mdi $$config{pipeline}{name}[0] rollback <action> <last_successful_step> [data.yml] [OPTIONS]"
        )   
    }
    
    # get and check options
    parseAllOptions('rollback', $subjectAction);
    checkRestrictedTask($subjectAction);
    
    # do it
    doRollback($subjectAction, $statusLevel, 1);
}
sub doRollback {
    my ($subjectAction, $statusLevel, $exit) = @_;
    
    # request permission
    getPermission("Pipeline status will be permanently reset.") or releaseMdiGitLock(1);
    $ENV{PIPELINE_ACTION} = $subjectAction;
    $ENV{LAST_SUCCESSFUL_STEP} = $statusLevel;
    
    # do the work
    system("bash -c 'source $workflowScript; resetWorkflowStatus'");
    $exit and releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# print a more concise list of an action's options (mostly for developers)
#------------------------------------------------------------------------------
sub runOptions {
    
    # check for a proper request
    my ($targetAction, $required, $error) = @args;
    $targetAction or $error .= "missing action\n";
    my $cmd = getCmdHash($targetAction); 
    if(!$cmd){
        $targetAction and $error .= "unkown action: $targetAction\n";
        throwError(
            $error.
            "usage: mdi $$config{pipeline}{name}[0] options <action> [required]"
        );
    }
    
    # report a terse format of all options (or just required options)
    loadActionOptions($cmd); # need options but no values    
    my @optionsOut = sort { lc($$a{short}[0]) cmp lc($$b{short}[0]) or
                               $$b{short}[0]  cmp    $$a{short}[0] or
                               $$a{long}[0]   cmp    $$b{long}[0] } values %longOptions;
    foreach my $option(@optionsOut){
        if(!$required or $$option{required}[0]){
            my $required = $$option{required}[0] ? "*REQUIRED*" : "";
            my $shortOut = $$option{short}[0];
            $shortOut = (!$shortOut or $shortOut eq 'null') ? "" : "-$$option{short}[0]";
            print join("\t", $shortOut, "--$$option{long}[0]", $required), "\n";
        }   
    }
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# print a tab-delimited table of all pipeline actions and options (mostly for Pipeline Runner)
#------------------------------------------------------------------------------
sub runOptionsTable { # takes no arguments
    my $launcher = loadYamlFile("$launcherDir/commands.yml", 0, 1, undef, 1);
    my %suppressedFamilies = map { $_ => 1 } ("job-manager", "workflow", "help");
    print join("\t", qw(pipelineName action optionFamily optionName 
                        type required universal order 
                        default description)), "\n";    
    foreach my $action(keys %{$$config{actions}}){
        $$launcher{actions}{$action} and next;
        my $cmd = getCmdHash($action); 
        loadActionOptions($cmd); # need options but no values, resets on each call
        my @optionsOut = sort { $$a{family}   cmp    $$b{family} } values %longOptions;
        foreach my $option(@optionsOut){
            my $family = $$option{family};
            $suppressedFamilies{$family} and next;
            my $universal = $$config{optionFamilies}{$family}{universal}[0] ? "UNIVERSAL" : "";
            my $order = $$option{order}[0] ? $$option{order}[0] : 9999;
            my $default = $$option{default}[0] eq 'null' ? "" : $$option{default}[0];
            $default eq "NA" and $default = "_NA_";
            my $required = $$option{required}[0] ? "TRUE" : "FALSE";
            print join("\t", $pipelineName, $action, $$option{family}, $$option{long}[0], 
                             $$option{type}[0], $required, $universal, $order,
                             $default, $$option{description}[0]), "\n";
        }    
    }
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# print a yaml-formatted string of parsed option values for <data>.yml (mostly for Pipeline Runner)
#------------------------------------------------------------------------------
sub runValuesYaml { # takes no arguments
    my $yaml = loadYamlFile($args[0], undef, undef, undef, 1); # suppress null entries

    # parse actions lists
    my %requestedActions = map { $_ => 1} ($$yaml{execute} ? @{$$yaml{execute}} : ());
    my $allActions = $$config{actions};
    foreach my $action (keys %$allActions){
        defined $$allActions{$action}{order} or $$allActions{$action}{order} = [999];
    }
    my @allActions = sort { 
        $$allActions{$a}{order}[0] <=> $$allActions{$b}{order}[0]
    } keys %$allActions;

    # initiate yaml
    my $yml = "---\n"; # will include values for _all_ actions
    $yml .= "pipeline: $pipelineName\n";
    my $actionsYml = "execute:\n"; # will include only the requested actions in <data>.yml
    my $indent = "    ";

    # parse options for all pipeline-specific actions
    foreach my $action(@allActions){
        $$allActions{$action}{universal}[0] and next;
        $requestedActions{$action} and $actionsYml .= "$indent- $action\n";        
        $yml .= "$action".":\n";
        my $cmd = getCmdHash($action);         
        parseAllOptions($action, undef, 1);
        parseAllDependencies($action);
        assembleActionYaml($action, $cmd, $indent, \my @taskOptions, \$yml);
    }

    # print the final yaml results
    print $yml.$actionsYml;
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# pre-pull a pipeline container for asynchronous, queued jobs to use (used by jobManager)
#------------------------------------------------------------------------------
sub checkContainer {
    # command has no options: mdi pipeline checkContainer <data.yml>
    # is silent unless needs to prompt for download
    pullPipelineContainer();
    releaseMdiGitLock(0);
}

#------------------------------------------------------------------------------
# build one container with all of a tool suite's pipelines and apps (cascades from jobManager)
#------------------------------------------------------------------------------
sub buildSuite {  
    my ($suite) = @_;
    my $usage = "usage: mdi buildSuite <GIT_USER/SUITE_NAME> [--version v0.0.0] [--sandbox]";
    my %options;
    my $sandbox = "sandbox"; # @args from jobManager is always (--version xxxx [--sandbox])
    $args[2] and ($args[2] eq '-s' or $args[2] eq "--$sandbox") and $options{$sandbox} = 1;   
    $suite or die "\nmissing suite\n$usage\n\n";
    buildSuiteContainer($suite, $options{$sandbox} ? "--sandbox" : "");
    exit;
}

1;
