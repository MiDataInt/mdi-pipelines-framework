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
    my ($action, $opts);
    if($options{'develop'}){
        $action = "develop";
        $opts = "";
    } elsif($options{'ondemand'}) {
        $action = "ondemand";
        $options{'ondemand-dir'} or throwError("option '--ondemand-dir' is required when option '--ondemand' is set", 'run');
        $opts = ", ondemandDir = \"".$options{'ondemand-dir'}."\"";
    } else {
        $action = "run";
        $opts = "";
    }
    my $dataDir = $options{'data-dir'} ? ", dataDir = \"".$options{'data-dir'}."\"" : "";
    exec "Rscript -e 'mdi::$action(mdiDir = \"$ENV{MDI_DIR}\" $dataDir $opts)'";
}
#========================================================================
            
1;
