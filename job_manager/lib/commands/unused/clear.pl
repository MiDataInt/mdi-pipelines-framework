use strict;
use warnings;

#========================================================================
# 'clear.pl' clears the error state of SGE jobs so that they will restart
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($schedulerDir %options %inError %targetJobIDs);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qClear { # clear all jobs in error state
    $options{'no-chain'} = 1;  # report action restricted to requested jobs
    checkLock();
    updateStatusQuietly();
    parseJobOption(\%inError, 'clear');  
    clearErrorState();
}
#========================================================================

#========================================================================
# clear job errors
#------------------------------------------------------------------------
sub clearErrorState { # rescue jobID and all of its successors
    my @jobIDs = sort {$a <=> $b} keys %targetJobIDs;
    if(@jobIDs){
        if($options{'dry-run'}){
            print "error states will be cleared from the following jobs:\n";
            showTargetJobs();
        } else {
            print "clearing error state(s)\n";
            my $inError = join(",", @jobIDs);
            my $qmod = qx|$schedulerDir/qmod -cj $inError|;
            print "$qmod";
            updateStatusFiles();    
        }
    } else {
        print "no jobs matching '--job $options{'job'}' are in error state Eqw\n";
    }
}
#========================================================================

1;

