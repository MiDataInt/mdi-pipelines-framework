use strict;
use warnings;

# subs for controlling the working version of pipeline suites
# through calls to git tag and git checkout

# working variables
use vars qw($target @args $pipelineDir $pipelineSuite);
my $silently = "> /dev/null 2>&1"; # bash suffix to suppress git messages
my $main       = 'main';
my $latest     = "latest";
my $preRelease = "pre-release";
my %versionDirectives = ($main => $main, $preRelease => $main, $latest => ''); # key = option value, value = git tag/branch
my %encounteredSuites; # a record of all suites whose version has already been adjusted
our $versions; # hash ref, filled by config.pl from pipeline.yml; can be undefined

# examine user options and set the primary pipeline suite version accordingly
sub setPipelineSuiteVersion {
    my $suiteDir = "$pipelineDir/../..";    
    my $version = getRequestedSuiteVersion();
    $encounteredSuites{$suiteDir}++;
    $version = convertSuiteVersion($suiteDir, $version);
    setSuiteVersion($suiteDir, $version, $pipelineSuite);
}

# parse and set the version for each newly encountered external suite that is invoked in pipeline.yml
sub setExternalSuiteVersion {
    my ($suiteDir, $suite) = @_;
    $encounteredSuites{$suiteDir} and return; # this suite was already handled on prior encounter
    $encounteredSuites{$suiteDir}++;
    my $version;
    if(!$versions or !$$versions{suites} or !$$versions{suites}{$suite}){
        $version = $latest; # apply the default directive when pipeline does not enforce external suite version
    } else {
        $version = $$versions{suites}{$suite};
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
    my ($version, $ymlFile);
                  $target  and $target  =~ m/\.yml$/ and $ymlFile = $target;  # call format: pipeline <data.yml> ...
    !$ymlFile and $args[0] and $args[0] =~ m/\.yml$/ and $ymlFile = $args[0]; # call format: pipeline action <data.yml> ...
    $ymlFile or return;
    my $yaml = loadYamlFile($ymlFile, undef, undef, undef, 1);
    $$yaml{pipeline} or throwError("malformed data.yml: missing pipeline declaration\n    $ymlFile\n");
    if(ref($$yaml{pipeline}) eq "HASH"){
        $$yaml{pipeline}{version} or return;
        $version = $$yaml{pipeline}{version}[0];
    } else { # yaml format: pipeline: name[=version]
        $$yaml{pipeline}[0] =~ m/.+=(.+)/ or return;
        $version = $1;
    }
    $version;
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
    $version =~ m/^\d+\.\d+\.\d+$/ and $version = "v$version"; # help user out if they specific 0.0.0 instead of v0.0.0
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
    system("cd $suiteDir; git checkout $version $silently") and 
        throwError(
            "unknown version directive for suite $suite: '$version'\n".
            "expected v#.#.#, a valid branch or tag, or one of ".join(", ", keys %versionDirectives)
        );
}

1;
