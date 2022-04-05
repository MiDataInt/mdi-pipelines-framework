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
my ($serverCmd, $singularityLoad, @containerSearchDirs);
my $silently = "> /dev/null 2>&1";
my $mdiCommand = 'server';
my $baseName = "mdi-singularity-base"; # disabled, see below
my $baseNameGlob = "$baseName/$baseName";
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
    $runtime eq 'direct' and return launchServerDirect();

    # determine whether system supports Singularity
    $singularityLoad = getSingularityLoadCommand();    

    # determine if and how the MDI installation supports Singularity
    #   NOTE 2022-04-05: disabled support for mdi-singularity-base due to stddef.h compile issues
    @containerSearchDirs = (
        $ENV{MDI_DIR}, 
        ($options{'host-dir'} and $options{'host-dir'} ne "NULL") ? $options{'host-dir'} : ()
    );    
    my $containerTypes = getAppsContainerSupport();

    # validate a request for running server via Singularity, without possibility for system fallback
    if($runtime eq 'container'){
        $singularityLoad or 
            throwError("--runtime 'container' requires Singularity on system or via config/singularity.yml >> load-command", $mdiCommand);            
        keys %$containerTypes or 
            throwError("--runtime 'container' requires container support from the tool suite or MDI installation", $mdiCommand);
    } 

    # dispatch the launch request to the proper handler
    !$singularityLoad and return launchServerDirect(); # runtime=auto, singularity not available
    $$containerTypes{suite} and return launchServerSuiteContainer();
    $$containerTypes{base}  and return launchServerBaseContainer($$containerTypes{base});
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
    exec "Rscript -e 'mdi::$serverCmd(mdiDir = \"$ENV{MDI_DIR}\", port = $options{'port'} $dataDir $hostDir)'";
}

# launch via Singularity with suite-level container
sub launchServerSuiteContainer {
    my $imageFile = getTargetAppsImageFile("$ENV{SUITE_NAME}/$ENV{SUITE_NAME}");
    launchServerContainer('suite', $imageFile);
} 

# launch via Singularity with extended mdi-singularity-base container
#   NOTE 2022-04-05: disabled support for mdi-singularity-base due to stddef.h compile issues
sub launchServerBaseContainer {
    throwError("ERROR: support for mdi-singularity-base is disabled", $mdiCommand);
    # my ($baseImageFiles) = @_;
    # my $imageFile = getTargetAppsImageFile($baseNameGlob, $baseImageFiles);
    # launchServerContainer('base', $imageFile);
} 

# common container run action
sub launchServerContainer {
    my ($imageType, $imageFile) = @_;
    -f $imageFile or 
        throwError("image file not found, please (re)install the apps server:\n    $imageFile", 'server');
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
    my $command = "echo $silently"; # first, see if it is already present and ready
    checkForSingularity($command) and return $command; 
    my $mdiDir = ($options{'host-dir'} and $options{'host-dir'} ne "NULL") ? $options{'host-dir'} : $ENV{MDI_DIR};
    my $ymlFile = "$mdiDir/config/singularity.yml"; # if not, attempt load-command from singularity.yml
    -e $ymlFile or return;
    my $yamls = loadYamlFromString( slurpFile($ymlFile) );
    $command = $$yamls{parsed}[0]{'load-command'};
    $command or return;
    $command = "$$command[0] $silently";
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

#========================================================================
# discover modes for apps server container support, if any
# containers must have been previously installed
#------------------------------------------------------------------------
#   NOTE 2022-04-05: disabled support for mdi-singularity base due to stddef.h compile issues
#------------------------------------------------------------------------
sub getAppsContainerSupport {
    my %types;
    suiteSupportsAppContainer() and $types{suite}++;
    # my @containers = getAvailableAppsContainers($baseNameGlob);
    # @containers and $types{base} = \@containers;
    \%types;
}
sub suiteSupportsAppContainer {
    $ENV{SUITE_MODE} and $ENV{SUITE_MODE} eq "suite-centric" or return;
    my $ymlFile = "$ENV{SUITE_DIR}/_config.yml";
    my $yamls = loadYamlFromString( slurpFile($ymlFile) );
    my $container = $$yamls{parsed}[0]{container} or return;
    my $supported = $$container{supported} or return;
    my $stages = $$container{stages} or return;
    my $hasApps = $$stages{apps} or return;
    $$supported[0] and $$hasApps[0];
}
sub getAvailableAppsContainers {
    my ($glob) = @_;
    my @files;
    foreach my $dir(@containerSearchDirs){
        push @files, glob("$dir/containers/$glob-*.sif"); # mdi-singularity-base-v4.1.sif
    }
    @files;
}
#========================================================================

#========================================================================
# get the requested/latest container version available _without_ pulling (install does that)
#------------------------------------------------------------------------
sub getTargetAppsImageFile {
    my ($glob, $imageFiles) = @_;
    $imageFiles or $imageFiles = [getAvailableAppsContainers($glob)]; 
    @$imageFiles or 
        throwError("no available container image files match pattern:\n    containers/$glob-*.sif", $mdiCommand);

    # if specific version requested, use it or fail trying   
    if(my $version = $options{'container-version'}){
        $version =~ m/^v/ or $version = "v$version"; # help user who type "0.0" instead of "v0.0"
        my $relPath = "containers/$glob-$version.sif";
        foreach my $imageFile(@$imageFiles){ # use the first encountered file, we don't care where it is located
            $imageFile =~ m/$relPath$/ and return $imageFile;
        }
        throwError("could not find container file:\n    $relPath", $mdiCommand);
    }

    # otherwise, default to latest available
    # don't check for latest again, let the install process do that
    my ($maxMajor, %maxMinor, %files);
    foreach my $imageFile(@$imageFiles){
        $imageFile =~ m/-v(\d+)\.(\d+)\.sif$/ or next;
        my ($major, $minor) = ($1, $2);
        (defined $maxMajor and $maxMajor >= $major) or $maxMajor = $major;
        (defined $maxMinor{$major} and $maxMinor{$major} >= $minor) or $maxMinor{$major} = $minor;
        $files{"$major.$minor"} = $imageFile; # again, just keep one, we don't care where it is
    }
    $files{"$maxMajor.$maxMinor{$maxMajor}"};
}#========================================================================

#========================================================================
# add a list of user-specified bind mounts to an apps-server container
#------------------------------------------------------------------------
sub addStage2BindMounts {
    my ($bind) = @_;
    my $ymlFile = "$ENV{MDI_DIR}/config/stage2-apps.yml";
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
