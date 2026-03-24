#!/usr/bin/perl
use strict;
use warnings;
use File::Path qw(make_path);
use File::Basename;

#========================================================================
# 'server.pl' launches the web server to use interactive Stage 2 apps
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options);
my ($serverCmd, $singularityLoad);
my $silently = "> /dev/null 2>&1";
my $mdiCommand = 'server';
my %serverCmds = map { $_ => 1 } qw(run develop remote node);
my $serverCmds = join(", ", keys %serverCmds);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub mdiServer { 

    # check the requested server command
    $serverCmd = $options{'server-command'};
    $serverCmds{$serverCmd} or 
        throwError("bad value for option '--server-command': $serverCmd\n"."expected one of: $serverCmds", $mdiCommand);

    # process a request for running server via system R, regardless of Singularity support
    my $runtime = $options{'runtime'};
    $runtime or $runtime = 'auto';
    ($runtime eq 'direct' or $runtime eq 'conda') and return launchServerDirect();

    # determine whether system supports Singularity
    $singularityLoad = getSingularityLoadCommand();

    # determine if and how the MDI installation supports Singularity
    my $ymlFile = "$ENV{SUITE_DIR}/_config.yml";
    my $yamls = loadYamlFromString( slurpFile($ymlFile) );
    my $containerConfig = $$yamls{parsed}[0]{container};
    my $suiteSupportsContainers = suiteSupportsAppContainer($containerConfig);

    # validate a request for running server via Singularity, without possibility for system fallback
    if($runtime eq 'container' or $runtime eq 'singularity'){
        $singularityLoad or 
            throwError("--runtime '$runtime' requires Singularity on system or via config/singularity.yml >> load-command", $mdiCommand);
        $suiteSupportsContainers or 
            throwError("--runtime '$runtime' requires container support from the tool suite", $mdiCommand);
    } 

    # dispatch the launch request to the proper handler
    !$singularityLoad and return launchServerDirect(); # runtime=auto, singularity not available
    $suiteSupportsContainers and return launchServerSuiteContainer($containerConfig);
    launchServerDirect(); # runtime=auto, singularity exists, but no means of container support
}
#========================================================================

#========================================================================
# process different paths to launching the server
#------------------------------------------------------------------------

# launch directly via system R
sub launchServerDirect {
    my $dataDir = $options{'data-dir'} ? ", dataDir = \"".$options{'data-dir'}."\"" : "";
    my $hostDir = $options{'host-dir'} ? ", hostDir = \"".$options{'host-dir'}."\"" : "";  
    my $R_COMMAND = qx/command -v Rscript/;
    chomp $R_COMMAND;
    $R_COMMAND or throwError(
        "FATAL: R program targets not found\n". 
        "please install or load R as required on your system\n".
        "    e.g., module load R/0.0.0\n".
        "and be sure you have installed the MDI apps interface on the remote server", 
        'server');
    my $R_VERSION = qx|Rscript --version|;
    $R_VERSION =~ m/version\s+(\d+\.\d+)/ and $R_VERSION =$1;
    my $LIB_PATH = "$ENV{MDI_DIR}/library/R-$R_VERSION"; # mdi-manager R package typically installed here
    exec "Rscript -e '.libPaths(\"$LIB_PATH\"); mdi::$serverCmd(mdiDir = \"$ENV{MDI_DIR}\", port = $options{'port'} $dataDir $hostDir)'";
}

# launch via Singularity with suite-level container
sub launchServerSuiteContainer {
    my ($containerConfig) = @_;
    my $imageFile = getTargetAppsImageFile($containerConfig);
    launchServerContainer('suite', $imageFile);
} 

# common container run action
sub launchServerContainer {
    my ($imageType, $imageFile) = @_;
    -f $imageFile or throwError("image file not found, please (re)install the apps server:\n    $imageFile", 'server');
    my $srvMdiDir  = "/srv/active/mdi";
    my $srvDataDir = "/srv/active/data";
    my $dataDir = $options{'data-dir'} ? $srvDataDir : "NULL";
    my $bind = "--bind $ENV{MDI_DIR}:$srvMdiDir";
    $options{'data-dir'} and $bind .= " --bind $options{'data-dir'}:$srvDataDir";
    addStage2BindMounts(\$bind); # add user bind paths from config/stage2-apps.yml
    my $port = $options{'port'} || 3838;
    my $singularityCommand = $ENV{SINGULARITY_COMMAND} || "run"; # for debugging, typically set to "shell"
    exec "$singularityLoad; singularity $singularityCommand $bind $imageFile apps $imageType $serverCmd $dataDir $port";
}
#========================================================================

#========================================================================
# discover Singularity on the system, if available
#------------------------------------------------------------------------
sub getSingularityLoadCommand {

    # first, see if singularity or apptainer command is already present and ready
    # NB: apptainer installations provide alias `singularity` to `apptainer`
    #     but commands report logs info as `apptainer`
    my $command = "echo $silently";
    checkForSingularity($command) and return $command; 
    
    # if not, attempt to use load-command from singularity.yml
    my $mdiDir = ($options{'host-dir'} and $options{'host-dir'} ne "NULL") ? $options{'host-dir'} : $ENV{MDI_DIR};
    my $ymlFile = "$mdiDir/config/singularity.yml";
    if(-e $ymlFile){
        my $yamls = loadYamlFromString( slurpFile($ymlFile) );
        $command = $$yamls{parsed}[0]{'load-command'};
        $command or return;
        $command = "$$command[0] $silently";
        checkForSingularity($command) and return $command;
    }

    # if not, attempt to use "module load singularity" as the default singularity load command
    $command = "module load singularity";
    checkForSingularity($command) and return $command;

    # no success
    undef;
}
sub checkForSingularity { # return TRUE if a proper singularity exists in system PATH after executing $command
    my ($command) = @_;
    system("$command; singularity --version $silently") and return; # command did not exist, system threw an error
    my $version = qx|$command; singularity --version|;
    $version =~ m/^(singularity|apptainer).+version.+/; # may fail if not a true singularity target (e.g., on greatlakes)
}
#========================================================================

#========================================================================
# discover modes for apps server container support, if any
#------------------------------------------------------------------------
sub suiteSupportsAppContainer {
    my ($containerConfig) = @_;
    $ENV{SUITE_MODE} and $ENV{SUITE_MODE} eq "suite-centric" or return;
    $containerConfig or return; # no container config at all, so no support
    my $supported = $$containerConfig{supported} or return;
    my $stages    = $$containerConfig{stages} or return;
    my $hasApps   = $$stages{apps} or return;
    $$supported[0] and $$hasApps[0];
}
#========================================================================

#========================================================================
# get the requested/latest container version available _without_ pulling (install does that)
#------------------------------------------------------------------------
sub getTargetAppsImageFile {
    my ($containerConfig) = @_;
    my $glob = "$ENV{MDI_DIR}/containers/".lc("$ENV{SUITE_NAME}/$ENV{SUITE_NAME}-apps"); # container names always lower case
    my $majorMinorVersion = $options{'container-version'} || getSuiteLatestVersion();
    $majorMinorVersion =~ m/^v/ or $majorMinorVersion = "v$majorMinorVersion"; # help user who type "0.0" instead of "v0.0"
    my $imageFile = "$glob-$majorMinorVersion.sif";
    ! -f $imageFile and pullSuiteContainer($containerConfig, $imageFile, $majorMinorVersion);
    return $imageFile;
}
sub getSuiteLatestVersion {
    my $suiteDir = "$ENV{MDI_DIR}/suites/definitive/$ENV{SUITE_NAME}"; # only definitive repos have semantic version tags
    my $tags = qx\cd $suiteDir; git checkout main $silently; git tag -l v*\; # tags that might be semantic version tags on main branch
    chomp $tags;
    my $error = "suite $ENV{SUITE_NAME} does not have any semantic version tags to use to recover container images\n";
    $tags or throwError($error, 'server');
    my @versions;
    foreach my $tag(split("\n", $tags)){
        $tag =~ m/v(\d+)\.(\d+)\.\d+/ or next; # ignore non-semvar tags; note that developer must use v0.0.0 (not 0.0.0)
        $versions[$1][$2]++;
    }
    @versions or throwError($error, 'server');
    my $major = $#versions;
    my $minor = $#{$versions[$major]};
    "v$major.$minor";
}
sub pullSuiteContainer {
    my ($containerConfig, $imageFile, $majorMinorVersion) = @_;
    my $registry  = $$containerConfig{registry}[0];
    my $owner     = $$containerConfig{owner}[0];
    my $packageName = lc "$ENV{SUITE_NAME}-apps"; # container names always lower case
    my $uri = "oras://$registry/$owner/$packageName:$majorMinorVersion";
    make_path(dirname($imageFile));
    print STDERR "pulling required container image...\n"; 
    system("$singularityLoad; singularity pull --disable-cache $imageFile $uri") and throwError(
        "container pull failed",
        'server'
    );
}
#========================================================================

#========================================================================
# add a list of user-specified bind mounts to an apps-server container
#------------------------------------------------------------------------
sub addStage2BindMounts {
    my ($bind) = @_;
    my $ymlFile = "$ENV{MDI_DIR}/config/stage2-apps.yml"; # TODO: add host-dir to this?
    -f $ymlFile or return;
    my $yamls = loadYamlFromString( slurpFile($ymlFile) );
    my $paths = $$yamls{parsed}[0]{paths} or return;
    ref($paths) eq 'HASH' or return;
    my %bound = ($ENV{MDI_DIR} => 1);
    $options{'data-dir'} and $bound{$options{'data-dir'}}++;
    foreach my $name(keys %$paths){
        ref($$paths{$name}) eq 'ARRAY' or next;
        my $dir = $$paths{$name}[0] or next;
        -d $dir or next;
        $bound{$dir} and next; # prevent duplicate binds
        $$bind .= " --bind $dir";
        $bound{$dir}++;
    }
}
#========================================================================

1;
