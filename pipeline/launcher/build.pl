use strict;
use warnings;

# subs for building and posting a Singularity container image of a pipeline

use vars qw($pipelineSuite $pipelineName $pipelineDir $pipelineSuiteDir $launcherDir);
our %installers = (
    ubuntu => 'apt-get'
);

sub buildSingularity {
    my ($suiteVersion) = @_; # is never undef as called by runBuild

    # get permission to create and post the Singularity image
    getPermission("\n'build' will create and post a Singularity container image for $pipelineSuite/$pipelineName=$suiteVersion") or exit;

    # parse the suite and pipeline versions to build
    $suiteVersion = convertSuiteVersion($pipelineSuiteDir, $suiteVersion);
    setSuiteVersion($pipelineSuiteDir, $suiteVersion, $pipelineSuite);

    # TODO: working here, need to load pipeline.yml to read the declared version
    # abort if no version found
    # NB: do NOT use suite version to label the container, as suite versions might change even when this pipeline hasn't!
    my $pipelineVersion = ;

    # create containers/pipelineName directory if missing
    my $containersDir = "$ENV{MDI_DIR}/containers";
    -d $containersDir or mkdir $containersDir;
    my $containerDir = "$containersDir/$pipelineName";
    -d $containerDir or mkdir $containerDir;

    # concatenate the complete Singularity container definition file
    my $pipelineDef = slurpContainerDef("$pipelineDir/singularity.def");
    $pipelineDef =~ m/From:\s+(\S+):.+/ or throwError("missing or malformed 'From:' declaration in singularity.def");
    my $linuxDistro = $1;
    my $commonDef = slurpContainerDef("$launcherDir/build-common.def");
    my $containerDef = "$pipelineDef\n\n$commonDef";

    # replace placeholders with pipeline-specific values (Singularity does not offer def file variables)
    my %vars = (
        SUITE_NAME          => $pipelineSuite,
        SUITE_VERSION       => $suiteVersion,
        PIPELINE_NAME       => $pipelineName,
        PIPELINE_VERSION    => $pipelineVersion,
        LINUX_DISTRIBUTION  => $linuxDistro,
        INSTALLER           => $installers{$linuxDistro} || 'apt-get'
    );
    foreach my $varName(keys %vars){
        $containerDef =~ s/__$varName__/$vars{$varName}/;
    }

    # commit the complete Singularity container definition file to mdi/containers
    my $imagePrefix = "$containerDir/$pipelineName-$pipelineVersion";
    my $defFile   = "$imagePrefix.def";
    my $imageFile = "$imagePrefix.sif";

    # run singularity build
    system("cd $ENV{MDI_DIR}; singularity build --fakeroot --sandbox $imageFile $defFile");
}

# slurp the contents of a container definition file
slurpContainerDef {
    my ($defFile) = @_;
    -e $defFile or throwError("missing container definition file: $defFile");
    slurpFile($defFile);
}

1;
