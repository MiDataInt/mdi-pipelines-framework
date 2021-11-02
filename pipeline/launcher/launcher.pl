use strict;
use warnings;

# execute, i.e., launch, a pipeline
# called by the 'mdi' command line function
# configures the environment and launches pipeline worker script(s)

# collect the requested pipeline, command, data.yml, and option arguments
# pipelineName could be a pipeline name only, or be directed to a specific repository as suite/pipeline
# target could be a command, or a config file with embedded commands via 'execute' key
my ($pipelineName, $target, @args) = @ARGV;
my @pipelineName = reverse(split('/', $pipelineName, 2)); # thus [name, maybe a suite]
$pipelineName[1] and $ENV{PIPELINES_SUITE_NAMES} = $pipelineName[1]; # form 'mdi suite/pipelineName'
my $pipeline;

# discover the pipeline source and whether to use a developer or the definitive fork
# if not directed to a specific repository, use the first matching pipeline name in order found in mdi.yml
# developer-forks take precedence in developer mode, ignored otherwise
my %Forks = (definitive => "definitive", developer => "developer-forks");
sub getPipeline {
    my ($fork) = @_;
    foreach my $suite(split(" ", $ENV{PIPELINES_SUITE_NAMES})){
        my $pipelineDir = "$ENV{MDI_DIR}/suites/$fork/$suite/pipelines/$pipelineName[0]";
        -d $pipelineDir and return { directory => $pipelineDir, fork => $fork, 
                                     suite => $suite, name => $pipelineName[0] };
    }
}
$ENV{DEVELOPER_MODE} and $pipeline = getPipeline($Forks{developer});
!$pipeline and $pipeline = getPipeline($Forks{definitive});
!$pipeline and die "\nmdi error: not a known command or pipeline: $pipelineName\n\n"; 
$pipelineName = $$pipeline{name};

# working variables
our (%conda, %longOptions, %shortOptions, %optionArrays, %optionValues);

# various paths
our $pipelineDir = $$pipelineDir{directory};
$ENV{PIPELINE_DIR} = $pipelineDir;
our $sharedDir = "$pipelineDir/../../shared";
our $environmentsDir = "$sharedDir/environments";
our $optionsDir      = "$sharedDir/options";
our $modulesDir      = "$sharedDir/modules";
$ENV{MODULES_DIR}  = $modulesDir;
# our $_sharedDir = "$pipelineDir/../_shared";
# $ENV{SHARED_DIR}   = $_sharedDir;
our $launcherDir    = "$ENV{FRAMEWORK_DIR}/pipeline/launcher";
$ENV{LAUNCHER_DIR} = $launcherDir;
our $workFlowDir    = "$ENV{FRAMEWORK_DIR}/pipeline/workflow";
$ENV{WORKFLOW_DIR} = $workFlowDir;
our $workflowScript = "$workFlowDir/workflow.sh";
$ENV{WORKFLOW_SH}  = $workflowScript;
$ENV{SLURP} = "$ENV{FRAMEWORK_DIR}/shell/slurp";

our $configFile = "$pipelineDir/_assembly/mdi.yml";

# load launcher scripts
map { $_ =~ m/launcher\.pl$/ or require $_ } glob("$launcherDir/*.pl");

# load the composite pipeline configuration from files
# NB: this is not the user's data configuration, it defines the pipeline
our $config = loadPipelineConfig();
$ENV{PIPELINE_NAME} = $$config{pipeline}{name}[0] or throwError("missing pipeline name\n");

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
