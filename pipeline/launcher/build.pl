use strict;
use warnings;

# subs for building and posting a Singularity container image of a pipeline

use vars qw($pipelineSuite $pipelineName);

#------------------------------------------------------------------------------
# set the dependencies list for a pipeline action
#------------------------------------------------------------------------------
sub buildSingularity {
    my ($version) = @_;

    # TODO: get latest tagged version of suite
    if($version eq "latest"){
        
    }

    # get permission to create the and post the Singularity image
    getPermission("\nBuild action will create and post a Singularity container image for $pipelineSuite//$pipelineName=$version") or exit;

    # create containers/pipelineName directory if missing
    my $containersDir = "$ENV{MDI_DIR}/containers";
    -d $containersDir or mkdir $containersDir;
    my $containerDir = "$containersDir/$pipelineName";
    -d $containerDir or mkdir $containerDir;

    # pass container build parameters to def file
    # no, Singularity does not seem to have a mechanism for this
    sub printDefVar{
        my $tmpFile = "$ENV{MDI_DIR}/$_[0].tmp";
        open my $outH, ">", $tmpFile or die "$!\n";
        print $outH "$_[1]";
        close $outH;        
    }
    printDefVar('SUITE_NAME',       $pipelineSuite);
    printDefVar('PIPELINE_NAME',    $pipelineName);
    printDefVar('VERSION',         $version);

    # run singularity build
    my $defFile = "$ENV{MDI_DIR}/suites/definitive/$pipelineSuite/pipelines/$pipelineName/singularity.def";
    -e $defFile or throwError("missing container definition file: $defFile");
    my $imageFile = "$containerDir/xxx.sif";
    system("cd $ENV{MDI_DIR}; singularity build --fakeroot --sandbox $imageFile $defFile");



    # assembled concatenated singularity.def
    # singularity build into mdi/containers
    # post to oras url


}

1;
