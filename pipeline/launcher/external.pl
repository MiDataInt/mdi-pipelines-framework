use strict;
use warnings;

# helper functions to locate environment, module, or option files that are
# external to a pipeline suite, i.e., to be read from a different suite 
# (which must therefore also be installed into the working MDI path)
# external suite version requirements can be specified in pipeline.yml

# working variables
use vars qw($mdiDir $suitesDir);

# return the path to a requested shared component file
sub getSharedFile {
    my ($suiteSharedDir, $sharedTarget, $sharedType, $throwError) = @_;

    # simple case, shared file is in the calling pipeline    
    my $sharedFile = "$suiteSharedDir/$sharedTarget"; # could be a file or a directory
    -e $sharedFile and return $sharedFile;

    # syntax for calling an external shared file: suite//path/to/file
    if($sharedTarget =~ m|//|){ 
        my ($suite, $target) = split('//', $sharedTarget);
        $sharedFile = getExternalSharedFile($suite, $target, $sharedType);
        $sharedFile and return $sharedFile;
    } 

    # file not found
    $throwError and throwSharedFileError($sharedTarget, $sharedType);
    undef;
}
sub getExternalSharedFile {
    my ($suite, $sharedTarget, $sharedType) = @_;
    setExternalSuiteVersion($suite);
    my $suiteSharedDir = "$suitesDir/$suite/shared/$sharedType"."s";
    my $sharedFile = "$suiteSharedDir/$sharedTarget.yml";
    -e $sharedFile and return $sharedFile;
    undef;
}
sub throwSharedFileError {
    my ($sharedTarget, $sharedType) = @_;
    throwError("missing $sharedType target: ".$sharedTarget);
}

1;
