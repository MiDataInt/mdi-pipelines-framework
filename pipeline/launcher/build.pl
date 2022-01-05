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

    # create containers directory if missing
    # assembled concatenated singularity.def
    # singularity build into mdi/containers
    # post to oras url


}

1;
