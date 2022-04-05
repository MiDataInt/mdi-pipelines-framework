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

    # honor the request for installing developer forks of MDI repos
    $ENV{INSTALL_MDI_FORKS} = $options{'forks'} ? "TRUE" : "";

    # ensure that mdi 'install.sh' script is present
    # could be missing if initial installation was performed using mdi::install()
    my $installScriptName = "install.sh";
    my $installScriptPath = "$ENV{MDI_DIR}/$installScriptName";
    my $installScriptUrl  = "https://raw.githubusercontent.com/MiDataInt/mdi/main/$installScriptName";
    !-f $installScriptPath and system("cd $ENV{MDI_DIR}; wget $installScriptUrl");

    # pass the call to 'install.sh' script from repo MiDataInt/mdi
    my $installLevel = $options{'install-packages'} ? 2 : 1;
    $ENV{N_CPU} = $options{'n-cpu'} ? $options{'n-cpu'} : 1;
    if($installLevel == 2 and $ENV{N_CPU} == 1){
        getPermissionGeneral(
            "You are about to install the Stage 2 Apps server with only 1 CPU.\n\n".
            "It is strongly recommended to set option --n-cpu to use as many CPUs".
            "as reasonable to speed installation of the many required R packages."
        )
    }
    exec "bash $installScriptPath $installLevel";
}
#========================================================================

1;
