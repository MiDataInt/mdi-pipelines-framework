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
my $silently = "> /dev/null 2>&1";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiServer { 

    # parse the requested server action
    my $action = "run";
    if($options{'develop'}){
        $action = "develop";
    } elsif($options{'ondemand'}) {
        $action = "ondemand";
    }

    # if singularity is supported, use it to help run the server, to match handling by install
    my $singularityLoad = getSingularityLoadCommand();
    if($singularityLoad){

        # check to see if the suite-centric call offers suite-level container support
        if($ENV{SUITE_MODE} and $ENV{SUITE_MODE} eq "suite-centric"){
            my $ymlFile = "$ENV{SUITE_DIR}/_config.yml";
            my $yamls = loadYamlFromString( slurpFile($ymlFile) );
            my $container = $$yamls{parsed}[0]{container} or return launchServerBaseContainer();
            my $supported = $$container{supported} or return launchServerBaseContainer();
            my $stages = $$container{stages} or return launchServerBaseContainer();
            my $hasApps = $$stages{apps} or return launchServerBaseContainer();
            ($$supported[0] and $$hasApps[0]) or return launchServerBaseContainer();
            launchServerSuiteContainer();

        # otherwise, use mdi-singularity-base as a helper            
        } else {
            launchServerBaseContainer();
        }

    # otherwise, use system R to run the server directly
    } else {
        my $dataDir = $options{'data-dir'} ? ", dataDir = \"".$options{'data-dir'}."\"" : "";
        my $hostDir = $options{'host-dir'} ? ", hostDir = \"".$options{'host-dir'}."\"" : "";  
        exec "Rscript -e 'mdi::$action(mdiDir = \"$ENV{MDI_DIR}\" $dataDir $hostDir)'";
    }
}

# launch Singularity with suite-level container
sub launchServerSuiteContainer {
    my ($singularityLoad, $action) = @_;

# need to get latest suite version when not specified, from the current git head

    # write script to auto-detect most recent container version from containers dir
    # container-version option allows override

    my $imageFile = "$ENV{MDI_DIR}/containers/$ENV{SUITE_NAME}/$ENV{SUITE_NAME}-$rVersion.sif";
    launchServerContainer($singularityLoad, $action, $imageFile);
} 

# launch Singularity with mdi-singularity-base
sub launchServerBaseContainer {
    my ($singularityLoad, $action) = @_; 

    # TODO: probably a better way to automatically choose the most recent R version   
    my $rVersion = $options{'r-version'} or 
        throwError("option '--r-version' is required when Singularity is available on the system", $command);
    $rVersion =~ m/^v/ or $rVersion = "v$rVersion";

    my $name = "mdi-singularity-base";
    my $imageFile = "$ENV{MDI_DIR}/containers/$name/$name-$rVersion.sif";
    launchServerContainer($singularityLoad, $action, $imageFile);
} 
sub launchServerContainer {
    my ($singularityLoad, $action, $imageFile) = @_;
    -f $imageFile or 
        throwError("image file not found, please (re)install the apps server:\n    $imageFile", 'server');
    my $srvMdiDir  = "/srv/active/mdi";
    my $srvDataDir = "/srv/active/data";
    my $srvHostDir = "/srv/active/host";
    my $dataDir = $options{'data-dir'} ? $srvDataDir : "NULL";
    my $hostDir = $options{'host-dir'} ? $srvHostDir : "NULL";
    my $bind = "--bind $ENV{MDI_DIR}:$srvMdiDir";
    $options{'data-dir'} and $bind .= " --bind $options{'data-dir'}:$srvDataDir";
    $options{'host-dir'} and $bind .= " --bind $options{'host-dir'}:$srvHostDir";

    # I think maybe hostDir is /static/, runs in activeDir

    exec "$singularityLoad; singularity run $bind $imageFile apps $action $dataDir $hostDir";
}

# discover Singularity on the system, if available
sub getSingularityLoadCommand {

    # first, see if it is already present and ready
    my $command = "echo $silently";
    checkForSingularity($command) and return $command; 
    
    # if not, attempt to use load-command from singularity.yml
    my $ymlFile = "$ENV{MDI_DIR}/config/singularity.yml";
    -e $ymlFile or return;
    my $yamls = loadYamlFromString( slurpFile($ymlFile) );
    $command = $$yamls{parsed}[0]{'load-command'};
    $command or return;
    $command = "$command $silently";
    checkForSingularity($command) and return $command;
    undef;
}
sub checkForSingularity { # return TRUE if a proper singularity exists in system PATH after executing $command
    my ($command) = @_;
    system("$command; singularity --version $silently") and return; # command did not exist, system threw an error
    my $version = qx|$command; singularity --version|;
    $version =~ m/^singularity.+version.+/; # may fail if not a true singularity target (e.g., on greatlakes)
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
