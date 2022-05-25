use strict;
use warnings;

# ensure that only one MDI process is working on a suite's git repo at a time
# use a lock file to secure private repo access for the duration of a call to launcher

use vars qw($mdiDir $pipelineSuite $pipelineSuiteDir $errorSeparator);

# do not place the lock file in $pipelineSuiteDir since branch changes could wipe it out
# all calls to xxxMdiGitLock are guaranteed to have a valid $pipelineSuite
sub getMdiLockFile {
    "$mdiDir/suites/$pipelineSuite.lock";    
}
sub getSuiteGitLockFile {
    "$pipelineSuiteDir/.git/index.lock";
}

sub setMdiGitLock { 
    my $mdiLockFile = getMdiLockFile();      # placed by MDI
    my $gitLockFile = getSuiteGitLockFile(); # placed by git
    my $cumLockWaitUSec = 0;
    my $maxLockWaitUSec = ($ENV{GIT_LOCK_WAIT_SECONDS} || 30) * 1000 * 1000; # i.e., 30 seconds default, mdi submit sets this higher for array jobs
    while((-e $mdiLockFile or -e $gitLockFile) and 
          $cumLockWaitUSec <= $maxLockWaitUSec){ # wait for others to release their lock
        $cumLockWaitUSec or print STDERR "#waiting for suite lock(s) to clear";
        print ".";
        my $lockWaitUSec = rand(2) * 1000 * 1000; 
        $cumLockWaitUSec += $lockWaitUSec;
        usleep($lockWaitUSec);
    }
    $cumLockWaitUSec and print "\n";
    if(-e $mdiLockFile or -e $gitLockFile){
        print
            "\n$errorSeparator\n". 
            "suite directory is locked:\n".
            "    $pipelineSuiteDir\n".
            "if you know the suite is not in use, try deleting its lock files:\n".
            "    rm -f $mdiLockFile\n".
            "    rm -f $gitLockFile\n".
            "or calling 'mdi unlock'\n".
            "$errorSeparator\n\n";
        exit 1; # do _not_ use throwError as it clears the lock file placed by someone else
    }
    open TMPFILE, '>', $mdiLockFile and close TMPFILE or 
        die "\ncould not create lock file:\n    $mdiLockFile\n\n";
}

sub releaseMdiGitLock { # always called at the end of every launcher run
    my ($exitStatus) = @_; # omit exit status if, and only if, followed by call to exec
    $ENV{IS_DELAYED_EXECUTION} and return; # not applicable
    $pipelineSuite or exit $exitStatus;
    my $lockFile = getMdiLockFile();
    -e $lockFile and unlink $lockFile;
    defined $exitStatus and exit $exitStatus; # don't use die to avoid compile error from require of launcher
}

1;
