use strict;
use warnings;

# subs for building and posting a Singularity container image of a pipeline

use vars qw($launcherDir $config %workingSuiteVersions
            $pipelineSuite $pipelineName $pipelineDir $pipelineSuiteDir);
my %installers = (      # key   = Linux distribution, from singularity.def 'From: distro:version'
    ubuntu => 'apt-get' # value = the associated installer, one of 'apt-get', 'yum'
);                      # if distro not listed here, defaults to 'apt-get'
my @supportTypes = qw(unsupported supported required);

sub buildSingularity {
    my ($sandbox) = @_;
    my $suiteVersion = $workingSuiteVersions{$pipelineSuiteDir};

    # get permission to create and post the Singularity image
    pipelineSupportsContainers() or throwError(
        "nothing to build\n".
        "no action in pipeline $pipelineName supports containers\n".
        "add 'container: supported|required' to action(s) to enable container builds"
    );
    getPermission(
        "\n'build' will create and post a Singularity container image for:\n".
        "    $pipelineSuite/$pipelineName=$suiteVersion"
    ) or exit;   
    
    # parse the pipeline version to build
    # container labels only use major and minor versions; patches must not change software dependencies
    # we do NOT use suite versions to label containers as suite versions might change even when this pipeline hasn't   
    my $config = loadYamlFile("$pipelineDir/pipeline.yml"); # obtain pipeline version from suite-version-adjusted tool suite
    my $pipelineVersion = $$config{pipeline}{version};
    $pipelineVersion or throwError( # abort if no version found; it is required to build containers
        "missing pipeline version designation in configuration file:\n".
        "    $pipelineDir/pipeline.yml"
    );
    $$pipelineVersion[0] =~ m/v(\d+)\.(\d+)\.(\d+)/ or 
    $$pipelineVersion[0] =~ m/v(\d+)\.(\d+)/ or throwError(
        "malformed pipeline version designation in configuration file:\n".
        "    $$pipelineVersion[0]\n".
        "    $pipelineDir/pipeline.yml\n".
        "expected format: v0.0[.0]"
    );
    $pipelineVersion = "v$1.$2"; 

    # concatenate the complete Singularity container definition file
    my $pipelineDef = slurpContainerDef("$pipelineDir/singularity.def");
    $pipelineDef =~ m/\nFrom:\s+(\S+):\S+/ or 
    $pipelineDef =~ m/\nFrom:\s+(\S+)/ or throwError(
        "missing or malformed 'From:' declaration in singularity.def\n".
        "expected: From: distro[:version]"
    );
    my $linuxDistro = $1;
    my $linuxVersion = $pipelineDef =~ m/\nFrom:\s+\S+:(.+)/ ? $1 : "unspecified";
    my $commonDef = slurpContainerDef("$launcherDir/build-common.def");
    my $containerDef = "$pipelineDef\n$commonDef";

    # replace placeholders with pipeline-specific values (Singularity does not offer def file variables)
    my %vars = (
        SUITE_NAME          => $pipelineSuite,
        SUITE_VERSION       => $suiteVersion,
        PIPELINE_NAME       => $pipelineName,
        PIPELINE_VERSION    => $pipelineVersion,
        LINUX_DISTRIBUTION  => $linuxDistro,
        LINUX_VERSION       => $linuxVersion,
        INSTALLER           => $installers{$linuxDistro} || 'apt-get'
    );
    foreach my $varName(keys %vars){
        my $placeholder = "__".$varName."__";
        $containerDef =~ s/$placeholder/$vars{$varName}/g;
    }

    # set container directory and file paths
    my $nameVersion   = "$pipelineName-$pipelineVersion";
    my $containersDir = "$ENV{MDI_DIR}/containers";
    my $containerDir  = "$containersDir/$pipelineName";
    my $versionDir    = "$containerDir/$nameVersion";
    mkdir $containersDir; # make_path not necessarily available in container
    mkdir $containerDir;
    mkdir $versionDir;
    my $imagePrefix = "$versionDir/$nameVersion";
    my $defFile     = "$imagePrefix.def";
    my $imageFile   = "$imagePrefix.sif";

    # run singularity build
    open my $outH, ">", $defFile or die "$!\n";
    print $outH $containerDef;
    close $outH;
    system("cd $ENV{MDI_DIR}; singularity build --fakeroot $sandbox $imageFile $defFile");
}

# slurp the contents of a container definition file
sub slurpContainerDef {
    my ($defFile) = @_;
    -e $defFile or throwError("missing container definition file:\n    $defFile");
    slurpFile($defFile);
}

# determine whether _any_ action supports containers, i.e., if there is something for build to do
sub pipelineSupportsContainers {
    foreach my $action(keys %{$$config{actions}}){
        actionSupportsContainers($action) and return 1;
    }
    undef;
}

# parse the container support status for a given pipeline action
sub actionSupportsContainers {
    my ($action) = @_;
    getActionContainerFlag($action) ne "unsupported";
}
sub actionRequiresContainers {
    my ($action) = @_;
    getActionContainerFlag($action) eq "required";
}
sub getActionContainerFlag {
    my ($action) = @_;
    my %supportTypes = map { $_ => 1 } @supportTypes;
    my $container = $$config{actions}{$action}{container};    # only build environments for supported actions in containers
    $container = $container ? $$container[0] : "unsupported"; # actions default to unsupported; developers must actively use containers
    $supportTypes{$container} or throwError(
        "unrecognized value for 'container' for action '$action' in configuration file:\n".
        "    $pipelineDir/pipeline.yml".
        "expected one of: ".join(", ", @supportTypes)
    );
    $container;
}

1;
