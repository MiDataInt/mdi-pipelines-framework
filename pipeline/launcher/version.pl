use strict;
use warnings;

# subs for controlling the working version of pipeline suites
# through calls to git tag and git checkout

# working variables
use vars qw($target @args $config $pipelineDir $pipelineSuite $pipelineSuiteDir);
my $silently = "> /dev/null 2>&1"; # bash suffix to suppress git messages
my $main       = 'main';
my $latest     = "latest";
my $preRelease = "pre-release";
my %versionDirectives = ($preRelease => $main, $latest => ''); # key = option value, value = git tag/branch
our $pipelineSuiteVersions; # hash ref, filled by config.pl from pipeline.yml; can be undefined
our %workingSuiteVersions;  # the working version of all suites that have already been adjusted

# examine user options and set the primary pipeline suite version accordingly
sub setPipelineSuiteVersion { 
    my $version = getRequestedSuiteVersion();
    $version = convertSuiteVersion($pipelineSuiteDir, $version);
    setSuiteVersion($pipelineSuiteDir, $version, $pipelineSuite);
}

# parse and set the version for each newly encountered external suite that is invoked in pipeline.yml
sub setExternalSuiteVersion {
    my ($suiteDir, $suite) = @_;
    $workingSuiteVersions{$suiteDir} and return; # this suite was already handled on prior encounter
    my $version;
    if(!$pipelineSuiteVersions or !$$pipelineSuiteVersions{$suite}){
        $version = $latest; # apply the default directive when pipeline does not enforce external suite version
    } else {
        $version = $$pipelineSuiteVersions{$suite};
    }
    $version = convertSuiteVersion($suiteDir, $version);
    setSuiteVersion($suiteDir, $version, $suite);
}

# examine user options for the requested pipeline suite version
sub getRequestedSuiteVersion {
    my $version = getCommandLineVersionRequest();      # command line options take precedence
    $version or $version = getJobFileVersionRequest(); # otherwise, search data.yml for a version setting
    $version; # otherwise, will default to latest
}
sub getJobFileVersionRequest {
    my $ymlFile;
                  $target  and $target  =~ m/\.yml$/ and $ymlFile = $target;  # call format: pipeline <data.yml> ...
    !$ymlFile and $args[0] and $args[0] =~ m/\.yml$/ and $ymlFile = $args[0]; # call format: pipeline action <data.yml> ...
    $ymlFile or return;
    my $yaml = loadYamlFile($ymlFile, undef, undef, undef, 1);
    $$yaml{pipeline} or throwError("malformed data.yml: missing pipeline declaration\n    $ymlFile\n");
    $$yaml{pipeline}[0] =~ m/.+:(.+)/ or return; # format \[pipelineSuite/\]pipelineName\[:suiteVersion\]
    $1;
}

# change version requests to git tags or branches
# this sub always returns a value, never undefined
sub convertSuiteVersion {
    my ($suiteDir, $version) = @_;
    $version or $version = $latest; # apply the default directive when version is missing
    if($version eq $latest){
        $version = getSuiteLatestVersion($suiteDir);
    } elsif($versionDirectives{$version}) {
        $version = $versionDirectives{$version};
    } # else request is a branch or non-semvar tag name (so could be ~anything) 
    $version =~ m/^\d+\.\d+\.\d+$/ and $version = "v$version"; # help user out if they specified 0.0.0 instead of v0.0.0
    $workingSuiteVersions{$suiteDir} = $version;
    $version; 
}

# use git+perl to determine the most recent semantic version of a pipeline suite on branch main
# method is robust to vagaries of tagging, git versions, etc.
sub getSuiteLatestVersion {
    my ($suiteDir) = @_; 
    my $tags = qx\cd $suiteDir; git checkout main $silently; git tag -l v*\; # tags that might be semantic version tags on main branch
    chomp $tags;
    $tags or return $main; # tags is empty string if suite has no semantic version tags -> use tip of main
    my @versions;
    foreach my $tag(split("\n", $tags)){
        $tag =~ m/v(\d+)\.(\d+)\.(\d+)/ or next; # ignore non-semvar tags; note that developer most use v0.0.0 (not 0.0.0)
        $versions[$1][$2][$3]++;
    }
    @versions or return $main; # there are tags on main, but none are semvar tags
    my $major = $#versions;
    my $minor = $#{$versions[$major]};
    my $patch = $#{$versions[$major][$minor]};
    "v$major.$minor.$patch";
}

# use git to check out the proper version of a pipelines suite
sub setSuiteVersion {
    my ($suiteDir, $version, $suite) = @_; # version might be a branch name or any valid tag
    my $gitCommand = "cd $suiteDir; git checkout $version"; # normally, we don't need to report git comments to user
    if(system("$gitCommand $silently")){
        print "\n";
        system($gitCommand); # repeat non-silently so user can see exactly what error git is reporting
        throwError(
            "unknown or unusable version directive for suite $suite: '$version'\n".
            "expected v#.#.#, a tag or branch, pre-release or latest (the default)"
        );        
    }
}

# get the version of a pipeline (not its suite) suitable for container tagging
sub getPipelineMajorMinorVersion {
    my $pipelineVersion = $$config{pipeline}{version};
    $pipelineVersion or throwError( # abort if no version found; it is required to build containers
        "missing pipeline version designation in configuration file:\n".
        "    $pipelineDir/pipeline.yml"
    );
    $$pipelineVersion[0] =~ m/v(\d+)\.(\d+)\.(\d+)/ or 
    $$pipelineVersion[0] =~ m/v(\d+)\.(\d+)/ or throwError(
        "malformed pipeline version designation in configuration file:\n".
        "    $$pipelineVersion[0]\n".
        "    $pipelineDir/pipeline.yml\n".
        "expected format: v0.0[.0]"
    );
    "v$1.$2"; 
}

1;
