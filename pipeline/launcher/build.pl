use strict;
use warnings;
use File::Path qw(make_path remove_tree);

# subs for building, posting and using a Singularity container image of a pipeline or suite

# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token

use vars qw($mdiDir $launcherDir $config %workingSuiteVersions @args
            $pipelineSuite $pipelineName $pipelineDir $pipelineSuiteDir);
my $silently = "> /dev/null 2>&1";

#------------------------------------------------------------------------------
# top level subs for building containers
#------------------------------------------------------------------------------

# build a pipeline-level container
sub buildSingularity {
    my ($sandbox, $force) = @_;
    my $suiteVersion = $workingSuiteVersions{$pipelineSuiteDir};

    # check to see if suite supports suite-level containers with pipelines installed
    # if so, no point in building pipeline-level containers
    suiteSupportsContainers() and getSuiteContainerStage('pipelines') and throwError(
        "suite '$pipelineSuite' supports a suite-level container with installed pipelines\n".
        "pipeline-level containers are superfluous and unnecessary\n".
        "aborting container build"
    );

    # get permission to create and post the Singularity image
    pipelineSupportsContainers() or throwError(
        "nothing to build\n".
        "pipeline $pipelineName does not support containers\n".
        "add/edit section 'container:' in pipeline.yml to enable container support"
    );
    getPermission(
        "\n'build' will create and post a Singularity container image for pipeline:\n".
        "    $pipelineSuite/$pipelineName:$suiteVersion"
    ) or releaseMdiGitLock(1); 
  
    # parse the pipeline version to build
    # container labels only use major and minor versions; patches must not change software dependencies
    # we do NOT use suite versions to label containers as suite versions might change even when this pipeline hasn't   
    my $pipelineVersion = getPipelineMajorMinorVersion();

    # assemble the complete container definition
    my $containerDef = assembleContainerDef($pipelineDir, "build-common", {
        SUITE_VERSION    => $suiteVersion,
        PIPELINE_NAME    => $pipelineName,
        PIPELINE_VERSION => $pipelineVersion
    });

    # build and push    
    buildAndPushContainer($containerDef, $pipelineVersion, $sandbox, $force)
}

# build a suite-level container
sub buildSuiteContainer {
    my ($suite) = @_;
    my ($gitUser, $repoName) = split('/', $suite);
    $repoName or throwError(
        "bad value for option '--suite', expected 'GIT_USER/SUITE_NAME'"
    );
    $pipelineSuite = $repoName;

    # parse and check the suite version
    # only allow latest and v0.0.0 so that a suite release can be checked out
    my $version = getRequestedSuiteVersion();
    $version or $version = "latest";
    $version =~ m/^\d+\.\d+\.\d+$/ and $version = "v$version"; # help user out if they specified 0.0.0 instead of v0.0.0
    $version eq "latest" or $version =~ m/v\d+\.\d+\.\d+/ or throwError(
        "bad value for '--version', expected 'latest' or form 'v0.0.0'"
    );

    # clone a fresh copy of the suite repository
    my $lcPipelineSuite = lc($pipelineSuite); # container names must be lower case for registry
    my $containerDir = "$ENV{MDI_DIR}/containers/$lcPipelineSuite";
    make_path $containerDir;
    my $tmpDir = "$ENV{MDI_DIR}/containers/tmp";
    mkdir $tmpDir;
    $pipelineSuiteDir = "$tmpDir/$pipelineSuite";  
    remove_tree $pipelineSuiteDir;
    system("cd $tmpDir; git clone https://github.com/$suite.git") and throwError(
        "git clone failed"
    );

    # set the suite version
    setPipelineSuiteVersion($version);
    my $status = qx\cd $pipelineSuiteDir; git status\;
    $status =~ m/detached/ or throwError( # always expect head to be detached at a suite version tag
        "bad value for '--version', expected 'latest' or form 'v0.0.0'\n".
        "alternatively, perhaps suite '$suite' does not have any version tags?"
    );
    my ($suiteVersion, $suiteMajorMinorVersion);
    $status =~ m/(v\d+\.\d+\.\d+)/ and $suiteVersion = $1;
    $suiteVersion =~ m/(v\d+\.\d+)\.\d+/ and $suiteMajorMinorVersion = $1;

    # parse the suite config and check whether it supports containers
    $config = loadYamlFile("$pipelineSuiteDir/_config.yml");
    suiteSupportsContainers($config) or throwError(
        "nothing to build\n".
        "suite '$suite' does not support containers\n".
        "add/edit section 'container:' in _config.yml to enable container support"
    );

    # determine the code stages to installs within the container
    my $addStage1 = getSuiteContainerStage('pipelines', $config);
    my $addStage2 = getSuiteContainerStage('apps',      $config);
    $addStage1 or $addStage2 or throwError(
        "nothing to build\n".
        "container:stages:pipelines and container:stages:apps are both false"
    );    
    getPermission(
        "\n'build' will create and post a Singularity container image for suite:\n".
        "    $suite:$suiteVersion"
    ) or exit;

    # assemble the complete container definition
    my $containerDef = assembleContainerDef($pipelineSuiteDir, "build-suite-common", {
        SUITE_VERSION            => $suiteVersion,
        SUITE_CONTAINER_VERSION  => $suiteMajorMinorVersion,
        MDI_FORCE_GIT            => "true", # flags for suite-centric install.sh
        MDI_INSTALL_PIPELINES    => $addStage1 ? "true" : "",
        MDI_FORCE_APPS           => $addStage2 ? "true" : "",
        MDI_SKIP_APPS            => $addStage2 ? "" : "true",    
        HAS_PIPELINES            => $addStage1 ? "true" : "false",
        HAS_APPS                 => $addStage2 ? "true" : "false"
    });

    # build and push  
    buildAndPushContainer($containerDef, $suiteMajorMinorVersion, "", "", 1)
}

#------------------------------------------------------------------------------
# actions subs shared by buildSingularity and buildSuiteContainer
#------------------------------------------------------------------------------

# assemble a complete singularity definition file
sub assembleContainerDef {
    my ($rootDir, $commonDef, $replace) = @_;

    # concatenate the complete Singularity container definition file
    my $def = slurpContainerDef("$rootDir/singularity.def");
    $def =~ m/\nFrom:\s+(\S+):\S+/ or $def =~ m/\nFrom:\s+(\S+)/ or throwError(
        "missing or malformed 'From:' declaration in singularity.def\n".
        "expected: From: base[:version]"
    );
    my $containerBase = $1;
    my $containerBaseVersion = $def =~ m/\nFrom:\s+\S+:(.+)/ ? $1 : "unspecified";
    $def = $def.slurpContainerDef("$launcherDir/$commonDef.def");

    # replace placeholders with pipeline-specific values (Singularity does not offer def file variables)
    my %vars = (
        SUITE_NAME     => $pipelineSuite,
        CONTAINER_BASE => $containerBase,
        CONTAINER_BASE_VERSION => $containerBaseVersion,
        INSTALLER => $$config{container}{installer} ? $$config{container}{installer}[0] : 'apt-get'
    );
    foreach my $varName(keys %vars){
        my $placeholder = "__".$varName."__";
        $def =~ s/$placeholder/$vars{$varName}/g;
    }
    foreach my $varName(keys %$replace){ # level-specific replacement, i.e., suite or pipeline
        my $placeholder = "__".$varName."__";
        $def =~ s/$placeholder/$$replace{$varName}/g;
    }
    $def;
}

# build and push a pipeline-level or suite-level container
sub buildAndPushContainer {
    my ($containerDef, $majorMinorVersion, $sandbox, $force, $isSuite) = @_;

    # set the output file and registry paths
    my $uris = getContainerUris($majorMinorVersion, $isSuite);

    # learn how to use Singularity on the system
    my $singularityLoad = getSingularityLoadCommand(1);
    my $singularity = "$singularityLoad; singularity";

    # run singularity build
    if(-e $$uris{imageFile} and !$force and $isSuite){ # for buildSuiteContainer
        print "\nSingularity container image already exists:\n";
        print "    $$uris{imageFile}\n";
        print "Should the container image be rebuilt?\n";
        print "Type 'y' for 'yes' to rebuild the container: (y|n) ";
        my $response = <STDIN>;
        chomp $response;
        $force = (uc(substr($response, 0, 1)) eq "Y");
        $force and $force = "--force";
    }
    if(! -e $$uris{imageFile} or $force){
        print "\nbuilding Singularity container image:\n    $$uris{imageFile}\nfrom:\n    $$uris{defFile}\n\n";          
        make_path($$uris{imageDir});
        open my $outH, ">", $$uris{defFile} or throwError($!);
        print $outH $containerDef;
        close $outH;
        system("$singularity build --fakeroot $sandbox $force $$uris{imageFile} $$uris{defFile}") and throwError(
            "container build failed"
        );        
    } elsif(!$isSuite) { # for buildSingularity, i.e., pipeline
        print "\nSingularity container image already exists:\n    $$uris{imageFile}\nuse option --force to re-build it\n";
    }

    # push container to registry
    # do this regardless of whether we just built it or it already existed
    print "\npushing Singularity container image:\n    $$uris{imageFile}\nto:\n    $$uris{container}\n\n";
    my $isLoggedIn = qx/$singularity remote list | grep '^$$uris{registry}'/; # singularity remote status does not work unless add is used
    chomp $isLoggedIn;
    if(!$isLoggedIn){
        print "Please log in: $$uris{owner}\@$$uris{registry}:\n";
        system("$singularity remote login --username $$uris{owner} $$uris{registry}") and throwError(
            "registry login failed"
        );
    }      
    system("$singularity push $$uris{imageFile} $$uris{container}") and throwError(
        "container push failed"
    );
}

#------------------------------------------------------------------------------
# pull a previously built pipeline container during job execution in mdi-centric mode
#------------------------------------------------------------------------------
sub pullPipelineContainer {
    my ($uris, $singularity) = @_;

    # do nothing if image was previously downloaded
    $uris or $uris = getContainerUris();
    -f $$uris{imageFile} and return;

    # get permission  
    getPermission(
        "\n$pipelineName wishes to download its Singularity container image:\n".
        "    $$uris{imageFile}\n".
        "from:\n".
        "    $$uris{container}"
    ) or releaseMdiGitLock(1);  

    # learn how to use singularity
    if(!$singularity){
        my $singularityLoad = getSingularityLoadCommand(1);
        $singularity = "$singularityLoad; singularity";        
    }      

    # create the target directory
    make_path($$uris{imageDir});

    # pull the image
    print "pulling required container image...\n"; 
    system("$singularity pull $$uris{imageFile} $$uris{container}") and throwError(
        "container pull failed"
    );
}

#------------------------------------------------------------------------------
# general container build and usage support functions
#------------------------------------------------------------------------------

# determine whether the pipeline or suite supports containers, i.e., if there is something for build to do
sub suiteSupportsContainers {
    my ($config) = @_;
    $config or $config = loadYamlFile("$pipelineSuiteDir/_config.yml");
    $$config{container} and 
    $$config{container}{supported} and 
    $$config{container}{supported}[0]
}
sub pipelineSupportsContainers {
    $$config{container} and 
    $$config{container}{supported} and 
    $$config{container}{supported}[0]
}

# get a flag whether a suite-level container supports stage 1 pipelines or stage 2 apps
# presumes that suiteSupportsContainers has already been checked
sub getSuiteContainerStage {
    my ($stage, $config) = @_;
    $config or $config = loadYamlFile("$pipelineSuiteDir/_config.yml");
    my $default = $stage eq 'pipelines' ? 1 : 0; # default to pipelines-only suite containers
    my $x = $$config{container} or return $default;
    $x = $$x{stages} or return $default;
    $x = $$x{$stage} or return $default;
    $$x[0];
} 

# slurp a container definition file
sub slurpContainerDef {
    my ($defFile) = @_;
    -e $defFile or throwError("missing container definition file:\n    $defFile");
    slurpFile($defFile);
}

# construct the URI to push/pull a pipeline container to/from a registry server
sub getContainerUris { # pipelineSupportsContainers(), i.e.,  $$config{container}{supported}, must already have been checked
    my ($majorMinorVersion, $isSuite) = @_;
    $majorMinorVersion or $majorMinorVersion = getPipelineMajorMinorVersion();
    my $cfg = $$config{container};
    my $registry = $$cfg{registry} ? $$cfg{registry}[0] : 'ghcr.io'; # default to MDI standard of GitHub Container Registry
    my $owner = $$cfg{owner} ? $$cfg{owner}[0] : '';
    my $configFileName = $isSuite ? "_config.yml" : "pipeline.yml";
    $owner or throwError(
        "missing owner for container registry $registry\n".
        "expected tag 'container: owner' in $configFileName"
    );
    my ($imageDir, $fileName, $packageName);
    my $lcPipelineSuite = lc($pipelineSuite); # container names must be lower case for registry
    if($isSuite){
        $imageDir = "$ENV{MDI_DIR}/containers/$lcPipelineSuite";
        $fileName = $lcPipelineSuite;
        $packageName = $lcPipelineSuite;
    } else {
        my $lcPipelineName  = lc($pipelineName);
        $imageDir = "$ENV{MDI_DIR}/containers/$lcPipelineSuite/$lcPipelineName";
        $fileName = $lcPipelineName;
        $packageName = "$lcPipelineSuite/$lcPipelineName";
    }
    {
        registry  => "oras://$registry",
        owner     => $owner,
        container => "oras://$registry/$owner/$packageName:$majorMinorVersion",
        imageDir  => $imageDir,
        defFile   => "$imageDir/$fileName-$majorMinorVersion.def",
        imageFile => "$imageDir/$fileName-$majorMinorVersion.sif"
    }
}

# make sure singularity is available on the system
sub getSingularityLoadCommand {
    my ($failIfMissing) = @_;

    # first, see if it is already present and ready
    my $command = "echo $silently";
    checkForSingularity($command) and return $command; 
    
    # if not, attempt to use singularity: load-command from stage1-pipelines.yml
    my $configYml = loadYamlFile("$mdiDir/config/stage1-pipelines.yml");
    if($$configYml{singularity} and $$configYml{singularity}{'load-command'}){
        my $command = "$$configYml{singularity}{'load-command'}[0] $silently";
        checkForSingularity($command) and return $command; 
    }

    # singularity failed, throw and error
    $failIfMissing and throwError(
        "could not find a way to load singularity from PATH or stage1-pipelines.yml"
    );
    "";
}
sub checkForSingularity { # return TRUE if a proper singularity exists in system PATH after executing $command
    my ($command) = @_;
    system("$command; singularity --version $silently") and return; # command did not exist, system threw an error
    my $version = qx|$command; singularity --version|;
    $version =~ m/^singularity.+version.+/; # may fail if not a true singularity target (e.g., on greatlakes)
}

1;
