use strict;
use warnings;

#========================================================================
# 'extend.pl' executes all previously unsatisfied commands specified by masterFile
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options %exists %extendable $separatorLength);
my $queryMessage = "At least one job command already exists in either the queued, running or completed state.\n".
                   "Continuing with 'q submit' will result in one or more duplicate identical jobs.";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qExtend { 
    $options{'_extending_'} = 1; # tell qSubmit to collect and obey extendability information    
    qSubmit();
}
#========================================================================

#========================================================================
# provide submit.pl with --delete option and extendability information
#------------------------------------------------------------------------
sub checkDeleteExtend {
    $options{'_suppress-echo_'} and return;  # true if this is a syntax check run for an execution request
    if($options{'delete'}){
        $options{'job'} = 'all';  # as instructions-level commands, submit/extend delete all jobs when --delete is set 
        qDelete();
        $options{'job'} = undef;  # reset options that aren't accepted by 'submit'
        $options{'no-chain'} = undef; 
        $options{'_extending_'} and $options{'force'} = undef;  # --force only applies to --delete part of extend, not the submission part
        $options{'force'} and %exists = ();
        print "~" x $separatorLength, "\n";
    } else {  
        $options{'_extending_'} and $options{'force'} = undef;
        $options{'force'} or updateStatusQuietly();
    } 
}  
sub checkExtendability { # don't resubmit jobs that were previosly satisfied = queued, running or completed
    my ($command) = @_;
    $exists{$command} or return 1;      # unknown jobs are always submittable
    $extendable{$command} and return 1; # extendable jobs are always submittable
    $options{_extending_} and return 0; # if 'q extend', known non-extendable jobs are ignored
    getPermission($queryMessage) and return 1;  # if 'q submit', ensure permission to requeue known non-extendable jobs
    print "'q submit' exiting.\nUse 'q extend' to submit only previously unsatisfied jobs.\n";
    exit;
}
#========================================================================
 
1;

