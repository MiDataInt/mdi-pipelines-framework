use strict;
use warnings;

# execute, i.e., launch, a pipeline
# called by the 'mdi' command line function
# configures the environment and launches pipeline worker script(s)

# collect the requested pipeline, command, data.yml, and option arguments
# target could be a command or a config file with embedded commands via 'execute' key
my ($pipelineName, $target, @args) = @ARGV;

# discover the pipeline target and whether to use developer or definitive fork
# use the first matching pipeline name in order given in mdi.yml
my ($pipelinesFile, $definitiveDir, $developerDir) = ("$ENV{MDI_DIR}/suites/pipelines.txt");
open my $pH, "<", $pipelinesFile or die "could not read file: $pipelinesFile: $!\n";
while (my $line = <$pH>){
    chomp $line;
    $line =~ m/$pipelineName\t(.*)\t(.*)/ or next;
    ($definitiveDir, $developerDir) = ($1, $2);
    last;
}
close $pH;
$definitiveDir or die "not a known command or pipeline: $pipelineName\n";
my $pipelineDir = ($ENV{DEVELOPER_MODE} and $developerDir) ? $developerDir : $definitiveDir;







# working variables

our ($pipelineDir) = @ARGV;

our ($pipelineName, %conda,
     %longOptions, %shortOptions, %optionArrays, %optionValues);

# various paths
$ENV{PIPELINE_EXECUTABLE} = $0;
$ENV{PIPELINE_DIR} = $pipelineDir;
our $mainDir = "$pipelineDir/../..";
our $environmentsDir = "$mainDir/environments";
our $optionsDir      = "$mainDir/options";
our $modulesDir      = "$mainDir/modules";
our $_sharedDir = "$pipelineDir/../_shared";
our $toolsDir = "$mainDir/tools";
our $launcherDir    = "$toolsDir/pipeline/launcher";
our $workFlowDir    = "$toolsDir/pipeline/workflow";
our $workflowScript = "$workFlowDir/workflow.sh";
our $configFile = "$pipelineDir/_assembly/mdi.yml";
$ENV{SLURP} = "$toolsDir/shell/slurp";
#$ENV{BED_UTIL} = "$toolsDir/shell/slurp";
$ENV{WORKFLOW_DIR} = $workFlowDir;
$ENV{WORKFLOW_SH}  = $workflowScript;
$ENV{SHARED_DIR}   = $_sharedDir;
$ENV{MODULES_DIR}  = $modulesDir;
$ENV{LAUNCHER_DIR} = $launcherDir;
$ENV{JOB_MANAGER_DIR} = "$mainDir/tools/job_manager";
 
# load launcher scripts
map { $_ =~ m/launcher\.pl$/ or require $_ } glob("$launcherDir/*.pl");

# load the composite pipeline configuration from files
# NB: this is not the user's data configuration
our $config = loadPipelineConfig();
$ENV{PIPELINE_NAME} = $$config{pipeline}{name}[0] or throwError("missing pipeline name\n");

# # requested command, data.yml, and option arguments
# # target could be a command or a config file with embedded commands via 'execute' key
# our ($target, @args) = @ARGV;

# establish lists of the universal options
our @universalOptionFamilies = sort {
    $$config{optionFamilies}{$a}{order}[0] <=> $$config{optionFamilies}{$b}{order}[0]
} map {
    $$config{optionFamilies}{$_}{universal}[0] ? $_ : ()
} keys %{$$config{optionFamilies}};
our @universalTemplateFamilies = sort {
    $$config{optionFamilies}{$a}{order}[0] <=> $$config{optionFamilies}{$b}{order}[0]
} map {
    $$config{optionFamilies}{$_}{template}[0] ? $_ : ()
} keys %{$$config{optionFamilies}};

# show top-level help for all pipeline commands; never returns
(!$target or $target eq '-h' or $target eq '--help') and showCommandsHelp(undef, 1);

# act on and typically terminate execution if target is a restricted command
doRestrictedCommand($target);

# act on potentially multiple commands taken from a data config file
our $isSingleCommand;
if ($target =~ m/\.yml$/) { 
    my $yaml = loadYamlFile($target);
    my %requestedCommands = map { $_ => 1 } $$yaml{execute} ? @{$$yaml{execute}} : ();
    my $cmds = $$config{commands}; # execute all requested commands in their proper order
    my @orderedCommands = sort { $$cmds{$a}{order}[0] <=> $$cmds{$b}{order}[0] } keys %$cmds;
    unshift @args, $target; # mimic format '<pipeline> <command> <data.yml> <options>' for each command
    my @argsCache = @args;
    foreach my $actionCommand(@orderedCommands){
        $$cmds{$actionCommand}{universal}[0] and next; # only execute pipeline commands
        $requestedCommands{$actionCommand} or next;    # only execute commands requested in data.yml
        executeCommand($actionCommand);
        @args = @argsCache; # reset args for next command
    }
    
# a single command specified on the command line    
} else {
    $isSingleCommand = 1;
    my $actionCommand = $target;
    executeCommand($actionCommand); # never returns
}

1;
