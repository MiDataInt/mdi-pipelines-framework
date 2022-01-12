use strict;
use warnings;

# subs for building and posting a Singularity container image of a pipeline

# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token

use vars qw($launcherDir $config %workingSuiteVersions
            $pipelineSuite $pipelineName $pipelineDir $pipelineSuiteDir);

sub buildSingularity {
    my ($sandbox, $force) = @_;
    my $suiteVersion = $workingSuiteVersions{$pipelineSuiteDir};

    # get permission to create and post the Singularity image
    pipelineSupportsContainers() or throwError(
        "nothing to build\n".
        "pipeline $pipelineName does not support containers\n".
        "add section 'container:' to pipeline.yml to enable container support"
    );
    getPermission(
        "\n'build' will create and post a Singularity container image for:\n".
        "    $pipelineSuite/$pipelineName:$suiteVersion"
    ) or exit;   
    
    # parse the pipeline version to build
    # container labels only use major and minor versions; patches must not change software dependencies
    # we do NOT use suite versions to label containers as suite versions might change even when this pipeline hasn't   
    my $pipelineVersion = getPipelineMajorMinorVersion();

    # concatenate the complete Singularity container definition file
    my $pipelineDef = slurpContainerDef("$pipelineDir/singularity.def");
    $pipelineDef =~ m/\nFrom:\s+(\S+):\S+/ or 
    $pipelineDef =~ m/\nFrom:\s+(\S+)/ or throwError(
        "missing or malformed 'From:' declaration in singularity.def\n".
        "expected: From: base[:version]"
    );
    my $containerBase = $1;
    my $containerBaseVersion = $pipelineDef =~ m/\nFrom:\s+\S+:(.+)/ ? $1 : "unspecified";
    my $commonDef = slurpContainerDef("$launcherDir/build-common.def");
    my $containerDef = "$pipelineDef\n$commonDef";

    # replace placeholders with pipeline-specific values (Singularity does not offer def file variables)
    my %vars = (
        SUITE_NAME       => $pipelineSuite,
        SUITE_VERSION    => $suiteVersion,
        PIPELINE_NAME    => $pipelineName,
        PIPELINE_VERSION => $pipelineVersion,
        CONTAINER_BASE   => $containerBase,
        CONTAINER_BASE_VERSION => $containerBaseVersion,
        INSTALLER        => $$config{container}{installer} ? $$config{container}{installer}[0] : 'apt-get'
    );
    foreach my $varName(keys %vars){
        my $placeholder = "__".$varName."__";
        $containerDef =~ s/$placeholder/$vars{$varName}/g;
    }

    # set container directory and file paths
    my $containerDir = "$ENV{MDI_DIR}/containers";
    mkdir $containerDir; 
    $containerDir = "$containerDir/$pipelineSuite";
    mkdir $containerDir;
    $containerDir = "$containerDir/$pipelineName";
    mkdir $containerDir;
    my $imagePrefix = "$containerDir/$pipelineName-$pipelineVersion";
    my $defFile     = "$imagePrefix.def";
    my $imageFile   = "$imagePrefix.sif";

    # run singularity build
    if(! -e $imageFile or $force){
        open my $outH, ">", $defFile or die "$!\n";
        print $outH $containerDef;
        close $outH;
        print "\nbuilding Singularity container image:\n    $imageFile\nfrom:\n    $defFile\n\n";    
        system("cd $ENV{MDI_DIR}; singularity build --fakeroot $sandbox $force $imageFile $defFile") and throwError(
            "container build failed"
        );        
    } else {
        print "\nSingularity container image already exists:\n    $imageFile\nuse option --force to re-build it\n";
    }

    # push container to registry
    my $uris = getContainerUris($pipelineVersion);  
    print "\npushing Singularity container image:\n    $imageFile\nto:\n    $$uris{container}\n\n";
    my $isLoggedIn = qx/singularity remote list | grep '^$$uris{registry}'/; # singularity remote status does not work unless add is used
    chomp $isLoggedIn;
    if(!$isLoggedIn){
        print "Please log in: $$uris{owner}\@$$uris{registry}:\n";
        system("cd $ENV{MDI_DIR}; singularity remote login --username $$uris{owner} $$uris{registry}") and throwError(
            "registry login failed"
        );
    }      
    system("cd $ENV{MDI_DIR}; singularity push $imageFile $$uris{container}") and throwError(
        "container push failed"
    );
}

# slurp the contents of a container definition file
sub slurpContainerDef {
    my ($defFile) = @_;
    -e $defFile or throwError("missing container definition file:\n    $defFile");
    slurpFile($defFile);
}

# determine whether the pipeline supports containers, i.e., if there is something for build to do
sub pipelineSupportsContainers {
    $$config{container} and 
    $$config{container}{supported} and 
    $$config{container}{supported}[0]
}

# construct the URI to push/pull a pipeline container to/from a registry server
sub getContainerUris { # pipelineSupportsContainers(), i.e.,  $$config{container}{supported}, must already have been checked
    my ($pipelineVersion) = @_;
    $pipelineVersion or $pipelineVersion = getPipelineMajorMinorVersion();
    my $cfg = $$config{container};
    my $registry = $$cfg{registry} ? $$cfg{registry}[0] : 'ghcr.io'; # default to MDI standard of GitHub Container Registry
    my $owner = $$cfg{owner} ? $$cfg{owner}[0] : '';
    $owner or throwError(
        "missing owner for container registry $registry\n".
        "expected tag 'container: owner' in pipeline.yml"
    );  
    {
        registry  => "oras://$registry",
        owner     => $owner,
        container => "oras://$registry/$owner/$pipelineSuite/$pipelineName:$pipelineVersion",
        imageFile => "$ENV{MDI_DIR}/containers/$pipelineSuite/$pipelineName/$pipelineName-$pipelineVersion.sif"
    }
}

1;
