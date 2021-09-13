#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'rollback.pl' restores status files to the most recently archived version
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $statusFile $archiveStem $separatorLength);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qRollback { 
    #checkLock();
    my $queryMessage = "'rollback' will:\n".
                       "   1) kill pending jobs, if any\n".
                       "   2) revert the status list to the last archive\n".                       
                       "   3) delete script and log files created since the last archive\n";
    $options{'dry-run'} or (getPermission($queryMessage) or exit);
    $options{'job'} = 'all'; # this is deleting all jobs, not just those being rolled back!
    qDelete();
    $options{'count'} or $options{'count'} = 1;
    print "~" x $separatorLength, "\n";
    my $feedbackMessage = $options{'dry-run'} ?
        "will roll back to status file" :
        "rolling back to status file";    
    print "$feedbackMessage:\n";
    my $archiveFile;
    foreach my $i(1..$options{'count'}){
        my $archiveNumber = getCurrentArchiveNumber();
        $archiveFile = "$archiveStem.$archiveNumber";        
        if(-e $archiveFile){
            purgeStatusFileTargets();
            $options{'dry-run'} or qx/mv $archiveFile $statusFile/;
        } else {
            print "  no remaining archive for $statusFile\n";
            exit;
        }
    }
    print "  $archiveFile\n";
}
#========================================================================

1;

