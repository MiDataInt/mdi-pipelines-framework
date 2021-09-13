#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'lock.pl' sets a protective marker that prevents any new job submission in a pipeline
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($masterFile);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qLock { # lock a master instructions file
    print "locking file:  $masterFile\n";
    my $lockFile = getLockFile();
    open my $outH, ">", $lockFile or die "could not open $lockFile for writing: $!\n";
    print $outH
        "\nMaster instructions file:\n\n".
        "    $masterFile\n\n".
        "has been locked against new job submission.\n".
        "Removing this file will remove the pipeline lock, or use:\n\n".
        "    q unlock $masterFile\n\n"; 
    close $outH;
}
sub qUnlock { # unlock a master instructions file
    print "unlocking file:  $masterFile\n";
    my $lockFile = getLockFile();
    unlink $lockFile;
}
#========================================================================

#========================================================================
# lock subroutines
#------------------------------------------------------------------------
sub checkLock {
    if(isLocked()){
        print "locked:   $masterFile\n";
        exit;
    }
}
sub getLockFile {
    return "$masterFile.lock"; 
}
sub isLocked { # locking is reflected by the simple presence of the lock file
    my $lockFile = getLockFile();
    return (-e $lockFile); 
}
#========================================================================

1;

