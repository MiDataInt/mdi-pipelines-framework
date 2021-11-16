use strict;
use warnings;

# helper functions to locate environment, module, or option files that are
# external to a pipeline suite, i.e., to be read from a different suite 
# (which must therefore also be installed into the working MDI path)

# working variables
use vars qw($mdiDir $suitesDir);

sub getSharedFile {
    my ($suiteSharedDir, $sharedTarget, $sharedType) = @_;
    my $sharedFile = "$suiteSharedDir/$sharedTarget.yml";
    if(-f $sharedFile){ # simple case, shared file is in the calling pipeline
        $sharedFile;
    } elsif($sharedTarget =~ m|//|){ # syntax for calling an external shared file: suite//path/to/file
        my ($suite, $target) = split('//', $sharedTarget);
        $sharedFile = getExternalSharedFile($suite, $target, $sharedType);
        !$sharedFile and throwSharedFileError($sharedTarget, $sharedType);
        $sharedFile;
    } else {
        throwSharedFileError($sharedTarget, $sharedType);
    } 
}
sub getExternalSharedFile {
    my ($suite, $sharedTarget, $sharedType) = @_;
    my $suiteSharedDir = "$suitesDir/$suite/shared/$sharedType"."s";
    my $sharedFile = "$suiteSharedDir/$sharedTarget.yml";
    -f $sharedFile and return $sharedFile;
    undef;
}
sub throwSharedFileError {
    my ($sharedTarget, $sharedType) = @_;
    throwError("missing $sharedType target: ".$sharedTarget);
}

1;
