use strict;
use warnings;

# subs for building and posting a Singularity container image of a pipeline

use vars qw($launcherDir $config %workingSuiteVersions
            $pipelineSuite $pipelineName $pipelineDir $pipelineSuiteDir);

sub buildSingularity {
    my ($sandbox) = @_;
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
    mkdir $containerDir; # make_path not necessarily available in container
    $containerDir = "$containerDir/$pipelineSuite";
    mkdir $containerDir;
    $containerDir = "$containerDir/$pipelineName";
    mkdir $containerDir;
    my $imagePrefix = "$containerDir/$pipelineName-$pipelineVersion";
    my $defFile     = "$imagePrefix.def";
    my $imageFile   = "$imagePrefix.sif";

    # run singularity build
    open my $outH, ">", $defFile or die "$!\n";
    print $outH $containerDef;
    close $outH;
    system("cd $ENV{MDI_DIR}; singularity build --fakeroot $sandbox $imageFile $defFile");

    # push container to registry

# ubuntu@ip-172-31-35-15:~$ TOKEN=xxxxx
# ubuntu@ip-172-31-35-15:~$ echo $TOKEN | singularity remote login --username xxxxx --password-stdin oras://ghcr.io
# singularity push test-v0.3.sif oras://ghcr.io/xxxxx/suite/pipeline:0.3
# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
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

1;
