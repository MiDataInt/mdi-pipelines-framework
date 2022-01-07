use strict;
use warnings;

# subs for controlling the working version of pipeline suites
# by calls to git tag and git checkout

# working variables
use vars qw($pipelineDir $pipelineSuite 
            $target @args);
my $main       = 'main';
my $latest     = "latest";
my $preRelease = "pre-release";
our %fixedVersions = ($main => $main, $preRelease => $main, $latest => ''); # key = option value, value = git tag/branch
our %actionSuites; # a record of all external suites called by a pipeline action

# read user options and set the primary pipeline suite version accordingly
sub setPipelineSuiteVersion {
    my $pipeline = loadYamlFile("$pipelineDir/pipeline.yml");
    my $version = getRequestedPipelineVersion();
    $version or $version = $latest;
    if($version eq $latest){
        $version = getSuiteLatestVersion();
    } elsif($fixedVersions{$version}) {
        $version = $fixedVersions{$version};
    }
    setSuiteVersion($pipelineDir, $pipelineSuite, $version);
}

# read user options for the requested pipeline suite version
sub getRequestedPipelineVersion {
    my $version = getCommandLineVersionRequest(); # command line options take precedence
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
        $version = $$yaml{pipeline}{version} or return;
    } else { # yaml format: pipeline: name[=version]
        $$yaml{pipeline} =~ m/.+=(.+)/ or return;
        $version = $1;
    }
    checkValidSuiteVersion($version, 'data.yml');
    $version;
}

# use git+perl to determine the most recent semantic version of a pipeline suite
# this method is robust to all vagaries of tagging, git versions, etc.
sub getSuiteLatestVersion {
    my $tags = qx\git tag -l v*\; # all tags that might be semantic version tags
    chomp $tags;
    $tags or return $main; # repo has no semantic version tags, use tip of main
    my @versions;
    foreach my $tag(split("\n", $tags)){
        $tag =~ m/v(\d+)\.(\d+)\.(\d+)/ or next;
        $versions[$1][$2][$3]++;
    }
    my $major = $#versions;
    my $minor = $#{$versions[$major]};
    my $patch = $#{$versions[$major][$minor]};
    "v$major.$minor.$patch";
}

# provide feedback on bad version
sub checkValidSuiteVersion {
    my ($version, $source);
    $fixedVersions{$version} or $version =~ m/v\d+\.\d+\.\d+/ or 
        throwError(
            "malformed $source: unusable value for pipeline suite version: $version\n".
            "expected v#.#.# or one of ".join(", ", keys %fixedVersions)
        ); 
}

# use git to check out the proper version of a pipelines suite
sub setSuiteVersion {
    my ($pipelineDir, $suite, $version) = @_; # version might be a branch name or a valid tag
    system("cd $pipelineDir/..; git checkout $version > /dev/null 2>&1") and 
        throwError("unknown version of suite $suite: $version");
}

1;
