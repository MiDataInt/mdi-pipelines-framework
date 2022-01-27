#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'server.pl' launches the web server to use interactive Stage 2 apps
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiServer { 
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

# #------------------------------------------------------
# # how MDI tools run on HPC servers
# # not applicable to public web server using AWS + Docker images
# #------------------------------------------------------
# # important to distinguish 'build' from 'install'
# #   developers build containers (end users never do) 
# #   users install tool support locally when not in a container or singularity not present
# #------------------------------------------------------
# # STAGE 1 PIPELINES - path depends on singularity and developer support; independent of centricity
# #------------------------------------------------------
# IF singularity and suite/pipeline supports containers
#   pipelines run via singularity using conda environments in versioned container (built by developer)
# ELSE
#   pipelines run directly using conda environments created locally by user
# #------------------------------------------------------
# # STAGE 2 APPS - path depends on singularity, developer support and centricity
# #------------------------------------------------------
# IF !singularity
#   apps run directly using system R and library installed locally by user 
# ELSE IF suite-centric (i.e., user launches a specific tool suite)
#   IF suite supports containers
#     apps run using R+library in the versioned container (built by developer); bind mount allows patch switching
#   ELSE
#     apps run using composite mdi-singularity-base/R+library (built by mdi) + mdi/containers/libary (installed by user)
# ELSE mdi-centric (i.e., user maintains a multi-suite installation)
#   apps run using composite mdi-singularity-base/R+library (built by mdi) + mdi/containers/libary (installed by user)
# #------------------------------------------------------

#------------------------------------------------------
# # disposition of MDI folders/files when apps server runs in a container
# #------------------------------------------------------
# # STATIC PATHS - installed in container, cannot change during run time
# #------------------------------------------------------
# frameworks
#   mdi-apps-framework
# library (implicitly in .libPaths() when mdi::run() called in container)
# resources **
# (suites code present from build but not used when running)
# #------------------------------------------------------
# # ACTIVE PATHS - in bind-mounted mdi folder
# #------------------------------------------------------
# config
#   stage2-apps.yml (called by running server to configure page, installation-specific)
# containers
#   library (installed (not built) by user to add tool suite support to mdi-singularity-base, add to .libPaths())
# data (written by user when using the server)
# resources **
# sessions (written by server per user encounter)
# suites
#   tool suite code (allows patch version switching, possibly more if library is sufficient)
# #------------------------------------------------------
# # NOT APPLICABLE to a running apps server
# #------------------------------------------------------
# config
#   singularity.yml (used to help launch, not run the server)
#   stage1-pipelines.yml
#   suites.yml (sets suites to install, not discover what is available while running)
# containers
#   tool suite... (the containers whose contents we are mapping!)
# environments
# frameworks
#   mdi-pipelines-framework
# remote (used to help launch, not run the server)
# #------------------------------------------------------
