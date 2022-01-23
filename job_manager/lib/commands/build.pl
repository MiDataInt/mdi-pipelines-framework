#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# build one container with all of a suite's pipelines and apps
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($rootDir $jobManagerName %options);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiBuild { 
    # pass this call to launcher, it already has support for building and versioning
    my $developerFlag = $ENV{DEVELOPER_MODE} ? "-d" : "";
    $options{'version'} or $options{'version'} = "latest";
    exec "$rootDir/$jobManagerName $developerFlag buildSuite $options{'suite'} --version $options{'version'}";
}
#========================================================================

1;
