#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'install.pl' re-runs the installation process to add new suites, etc.
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiInstall { 

    # TODO: must honor singularity if present
    # easiest past might be to always use ./install.sh (will it always be present?)
    # install-packages sets 1 vs. 2, etc.

    my $installPackages = $options{'install-packages'} ? "TRUE" : "FALSE";
    exec "Rscript -e 'mdi::install(\"$ENV{MDI_DIR}\", ".
         "installPackages = $installPackages, confirm = FALSE, addToPATH = FALSE, ".
         "clone = TRUE, force = FALSE)'";
}
#========================================================================

1;
