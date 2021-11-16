#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'run.pl' launches the web server to use interactive Stage 2 apps
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiRun { 
    my ($action, $opts) = ("", "");
    if($options{'develop'}){
        $action = "develop";
    } elsif($options{'ondemand'}) {
        $action = "ondemand";
    } else {
        $action = "run";
    }
    my $dataDir = $options{'data-dir'} ? ", dataDir = \"".$options{'data-dir'}."\"" : "";
    my $hostDir = $options{'host-dir'} ? ", hostDir = \"".$options{'host-dir'}."\"" : "";
    exec "Rscript -e 'mdi::$action(mdiDir = \"$ENV{MDI_DIR}\" $dataDir $hostDir $opts)'";
}
#========================================================================

1;
