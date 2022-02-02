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

    # ensure that mdi 'install.sh' script is present
    # could be missing if initial installation was performed using mdi::install()
    my $installScriptName = "install.sh";
    my $installScriptPath = "$ENV{MDI_DIR}/$installScriptName";
    my $installScriptUrl  = "https://raw.githubusercontent.com/MiDataInt/mdi/main/$installScriptName";
    !-f $installScriptPath and system("cd $ENV{MDI_DIR}; wget $installScriptUrl");

    # pass the call to 'install.sh' script from repo MiDataInt/mdi
    my $installLevel = $options{'install-packages'} ? 2 : 1;
    exec "bash $installScriptPath $installLevel";
}
#========================================================================

1;
