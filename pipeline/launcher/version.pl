use strict;
use warnings;

# subs for controlling the working version of pipeline suites
# by calls to git tag and git checkout

# working variables
use vars qw($target @args $pipelineDir $pipelineSuite);
my $main       = 'main';
my $latest     = "latest";
my $preRelease = "pre-release";
our %fixedVersions = ($main => $main, $preRelease => $main, $latest => ''); # key = option value, value = git tag/branch
# our %actionSuites; # a record of all external suites called by a pipeline action
our $versions; # hash ref, filled by other config.pl

# read user options and set the primary pipeline suite version accordingly
sub setPipelineSuiteVersion {
    my $suiteDir = "$pipelineDir/..";    
    my $version = getRequestedSuiteVersion();
    $version = convertSuiteVersion($suiteDir, $version);
    setSuiteVersion($suiteDir, $version, $pipelineSuite);
}
sub convertSuiteVersion {
    my ($suiteDir, $version) = @_;
    $version or $version = $latest;
    if($version eq $latest){
        $version = getSuiteLatestVersion($suiteDir);
    } elsif($fixedVersions{$version}) {
        $version = $fixedVersions{$version};
    } # else is a branch or non-semvar tag name   
    $version; 
}

# read user options for the requested pipeline suite version
sub getRequestedSuiteVersion {
    my $version = getCommandLineVersionRequest();      # command line options take precedence
    $version or $version = getJobFileVersionRequest(); # otherwise, search data.yml for a version setting
    $version;
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
    # checkValidSuiteVersion($version, 'data.yml');
    $version;
}

# parse and set the version for each newly encountered external suite that is invoked
sub setExternalSuiteVersion {
    my ($suite) = @_;

    # WORKING HERE
    my $suiteDir = "xxxxxx";    
    my $version;
    if(!$versions){
        $version = $latest;
    }
    $version = convertSuiteVersion($suiteDir, $version);
}

# TODO: delete - requested version could be an unpredictable developer branch name
# # provide feedback on bad version
# sub checkValidSuiteVersion {
#     my ($version, $source);
#     $fixedVersions{$version} or $version =~ m/v\d+\.\d+\.\d+/ or 
#         throwError(
#             "malformed $source: unusable value for pipeline suite version: $version\n".
#             "expected v#.#.# or one of ".join(", ", keys %fixedVersions)
#         ); 
# }

# use git+perl to determine the most recent semantic version of a pipeline suite
# method is robust to vagaries of tagging, git versions, etc.
sub getSuiteLatestVersion {
    my ($suiteDir) = @_; 
    my $tags = qx\cd $suiteDir; git tag -l v*\; # tags that might be semantic version tags
    chomp $tags;
    $tags or return $main; # repo has no semantic version tags, use tip of main
    my @versions;
    foreach my $tag(split("\n", $tags)){
        $tag =~ m/v(\d+)\.(\d+)\.(\d+)/ or next;
        $versions[$1][$2][$3]++;
    }
    @versions or return $main;
    my $major = $#versions;
    my $minor = $#{$versions[$major]};
    my $patch = $#{$versions[$major][$minor]};
    "v$major.$minor.$patch";
}

# use git to check out the proper version of a pipelines suite
sub setSuiteVersion {
    my ($suiteDir, $version, $suite) = @_; # version might be a branch name or any valid tag
    system("cd $suiteDir; git checkout $version > /dev/null 2>&1") and 
        throwError(
            "unknown version of suite $suite: $version\n".
            "expected v#.#.#, a valid branch or tag name, or one of ".join(", ", keys %fixedVersions)
        );
}

1;
