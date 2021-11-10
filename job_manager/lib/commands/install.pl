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
    my $installApps = $options{'install-apps'} ? "TRUE" : "FALSE";
    exec "Rscript -e 'mdi::install(\"$ENV{MDI_DIR}\", ".
         "installApps = $installApps, confirm = FALSE, addToPATH = FALSE, ".
         "clone = TRUE, force = FALSE)'";
}
#========================================================================

1;
