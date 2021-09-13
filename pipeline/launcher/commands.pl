use strict;
use warnings;

# subs for handling universal pipeline actions
# most commands terminate execution or never return

# working variables
use vars qw($pipelineDir $launcherDir $mainDir
            @args $config %longOptions $workflowScript);

# switch for acting on restricted commands
sub doRestrictedCommand {
    my ($target) = @_;
    my %restricted = (
        template => \&runTemplate,
        conda    => \&runConda,
        status   => \&runStatus,
        rollback => \&runRollback,
        options  => \&runOptions
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
    
    # if requested, show custom command help
    if($options{$help}){
        my $desc = getTemplateValue($$config{commands}{template}{description});
        my $pname = $$config{pipeline}{name}[0];
        print "\n$pname template: $desc\n";
        print  "\nusage: $pname template [-a/--$allOptions] [-c/--$addComments] [-h/--help]\n";
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
    my $defaultServerYml = Cwd::abs_path("$mainDir/server.yml");
    my @newArgs = ($args[0] and $args[$#args] =~ m/\.yml$/) ? (pop @args) : ();
    
    # special handling of command line option flags
    my %options;
    my $help   = "help";
    my $list   = "list";
    my $create = "create";
    my $force  = "force";
    foreach my $arg(@args){
        ($arg eq '-h' or $arg eq "--$help") and $options{$help}  = 1;        
        ($arg eq '-l' or $arg eq "--$list")  and $options{$list}  = 1;        
        ($arg eq '-c' or $arg eq "--$create") and $options{$create} = 1;
        ($arg eq '-f' or $arg eq "--$force") and $options{$force} = 1;
    }
    (!$options{$list} and !$options{$create}) and $options{$help}  = 1;     
    my $error = ($options{$list} and $options{$create}) ?
                "\noptions '--$list' and '--$create' are mutually exclusive\n" : "";
                
    # if requested, show custom command help
    my $pname = $$config{pipeline}{name}[0];
    if($options{$help} or $error){
        my $usage;
        my $desc = getTemplateValue($$config{commands}{conda}{description});
        $usage .= "\n$pname conda: $desc\n";
        $usage .=  "\nusage: $pname conda [options] [data.yml]\n";
        $usage .=  "\n    -l/--$list     show the yml config file for each pipeline command";
        $usage .=  "\n    -c/--$create   if needed, create the required conda environments";
        $usage .=  "\n    -f/--$force    do not prompt for permission to create environments";      
        $usage .= "\n\nif data.yml is provided it will be used to find conda:base-directory\n";
        $usage .= "otherwise will use the value found in $defaultServerYml\n";
        $error and throwError($error.$usage);
        print "$usage\n";
        exit;
    }
    
    # list or create conda environments in command order
    @args = @newArgs;
    showCreateCondaEnvironments($options{$create}, $options{$force});
    exit;
}

#------------------------------------------------------------------------------
# report on the current job completion status of the pipeline for a specific data directory
#------------------------------------------------------------------------------
sub runStatus {
    
    # check for a proper request
    my ($subjectCommand, $error);
    ($subjectCommand, @args) = @args;
    $subjectCommand or $error .= "missing command\n";
    my $cmd = getCmdHash($subjectCommand); 
    if(!$cmd){
        $subjectCommand and $error .= "unkown command: $subjectCommand\n";
        throwError(
            $error.
            "usage: $$config{pipeline}{name}[0] status <COMMAND> [data.yml] [OPTIONS]"
        )
    }
    
    # get and check options
    parseAllOptions('status', $subjectCommand);
    checkRestrictedTask($subjectCommand);
    
    # do the work
    print "\n";
    exec "bash -c 'source $workflowScript; showWorkflowStatus'";  
}

#------------------------------------------------------------------------------
# clear the job status for a specific data directory to force jobs to start anew
#------------------------------------------------------------------------------
sub runRollback {
    
    # check for a proper request
    my ($subjectCommand, $statusLevel, $error);
    ($subjectCommand, $statusLevel, @args) = @args;
    $subjectCommand or $error .= "missing command\n";
    my $cmd = getCmdHash($subjectCommand); 
    if(!$cmd or !defined $statusLevel){
        !$cmd and $subjectCommand and $error .= "unkown command: $subjectCommand\n";
        $statusLevel or $error .= "missing status level\n";
        throwError(
            $error.
            "usage: $$config{pipeline}{name}[0] rollback <COMMAND> <LAST_SUCCESSFUL_STEP> [data.yml] [OPTIONS]"
        )   
    }
    
    # get and check options
    parseAllOptions('rollback', $subjectCommand);
    checkRestrictedTask($subjectCommand);
    
    # do it
    doRollbackAction($subjectCommand, $statusLevel, 1);
}
sub doRollbackAction {
    my ($subjectCommand, $statusLevel, $exit) = @_;
    
    # request permission
    confirmAction("Pipeline status will be permanently reset.") or exit;
    $ENV{PIPELINE_COMMAND} = $subjectCommand;
    $ENV{LAST_SUCCESSFUL_STEP} = $statusLevel;
    
    # do the work
    system("bash -c 'source $workflowScript; resetWorkflowStatus'");
    $exit and exit;
}

#------------------------------------------------------------------------------
# print a more concise list of a command's options (mostly for developers)
#------------------------------------------------------------------------------
sub runOptions {
    
    # check for a proper request
    my ($targetCommand, $required, $error) = @args;
    $targetCommand or $error .= "missing command\n";
    my $cmd = getCmdHash($targetCommand); 
    if(!$cmd){
        $targetCommand and $error .= "unkown command: $targetCommand\n";
        throwError(
            $error.
            "usage: $$config{pipeline}{name}[0] options <COMMAND> [required]"
        );
    }
    
    # report a terse format of all options (or just required options)
    loadCommandOptions($cmd); # need options but no values    
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

1;

