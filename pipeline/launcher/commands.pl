use strict;
use warnings;

# subs for handling universal pipeline commands
# most terminate execution or never return

# working variables
use vars qw($pipeline $pipelineName $launcherDir $mdiDir
            @args $config %longOptions $workflowScript);

# switch for acting on restricted commands
sub doRestrictedCommand {
    my ($target) = @_;
    my %restricted = (
        template => \&runTemplate,
        conda    => \&runConda,
        status   => \&runStatus,
        rollback => \&runRollback,
        options  => \&runOptions, 
        optionsTable => \&runOptionsTable,
        valuesTable  => \&runValuesTable
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
        exit;
    }
    
    # print the template to STDOUT
    writeDataFileTemplate($options{$allOptions}, $options{$addComments});
    exit;
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
    my $help   = "help";
    my $list   = "list";
    my $create = "create";
    my $force  = "force";
    foreach my $arg(@args){
        ($arg eq '-h' or $arg eq "--$help")   and $options{$help}  = 1;        
        ($arg eq '-l' or $arg eq "--$list")   and $options{$list}  = 1;        
        ($arg eq '-c' or $arg eq "--$create") and $options{$create} = 1;
        ($arg eq '-f' or $arg eq "--$force")  and $options{$force} = 1;
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
        $usage .=  "\n    -l/--$list     show the yml config file for each pipeline action";
        $usage .=  "\n    -c/--$create   if needed, create the required conda environments";
        $usage .=  "\n    -f/--$force    do not prompt for permission to create environments";      
        $error and throwError($error.$usage);
        print "$usage\n\n";
        exit;
    }
    
    # list or create conda environments in action order
    @args = @newArgs;
    showCreateCondaEnvironments($options{$create}, $options{$force});
    exit;
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
    getPermission("Pipeline status will be permanently reset.") or exit;
    $ENV{PIPELINE_ACTION} = $subjectAction;
    $ENV{LAST_SUCCESSFUL_STEP} = $statusLevel;
    
    # do the work
    system("bash -c 'source $workflowScript; resetWorkflowStatus'");
    $exit and exit;
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
    exit;
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
    exit;
}

#------------------------------------------------------------------------------
# print a yaml-formatted string of parsed option values for <data>.yml (mostly for Pipeline Runner)
#------------------------------------------------------------------------------
sub runValuesTable { # takes no arguments
    my $yaml = loadYamlFile($args[0], undef, undef, undef, 1); # suppress null entries
    my @requestedActions = $$yaml{execute} ? @{$$yaml{execute}} : ();
    my $yml = "---\n";
    $yml .= "pipeline: $pipelineName\n";
    my $actionsYml = "execute:\n";
    my $indent = "    ";
    foreach my $action(@requestedActions){
        $yml .= "$action".":\n";
        my $cmd = getCmdHash($action);         
        parseAllOptions($action, undef, 1);
        parseAllDependencies($action);
        assembleActionYaml($action, $cmd, $indent, \my @taskOptions, \$yml);
        $actionsYml .= "$indent- $action\n";
    }
    print $yml.$actionsYml;
    exit;
}

1;
