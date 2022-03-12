#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'purge.pl' handles deletion/unlinking of outdated status, script and log files
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options %statusFields $statusFile $archiveStem $separatorLength);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qPurge { 
    #checkLock();
    my $queryMessage = "'purge' will:\n".
                       "   1) kill pending jobs, if any\n".
                       "   2) revert the status list to the empty state\n".                       
                       "   3) delete all script and log files\n";           
    $options{'dry-run'} or (getPermission($queryMessage) or return);
    $options{'job'} = 'all';
    qDelete();
    print "~" x $separatorLength, "\n";
    my $feedbackMessage = $options{'dry-run'} ?
        "the following status file will be purged" :
        "purging status file";
    print "$feedbackMessage:\n";
    -e $statusFile or die "could not find status file:  $statusFile\n";  
    print "  $statusFile\n";
    purgeStatusFileTargets(1);
    $options{'dry-run'} or unlink $statusFile;
}
#========================================================================

#========================================================================
# purge q-generated pipeline files (does not affect data output files)
#------------------------------------------------------------------------
sub purgeStatusFileTargets {
    my ($purgeArchives) = @_; 
    my %archivedJobs;
    $purgeArchives or getArchivedJobs(\%archivedJobs);
    open my $statusFileH, "<", $statusFile or return;
    while(my $line = <$statusFileH>){
        chomp $line;    
        my @line = split("\t", $line);   
        my $qType = $line[$statusFields{qType}];
        my $jobID = $line[$statusFields{jobID}];
        ($jobID and $jobID =~ m/^\d+$/) or next; # job lines and only job lines have jobID field all digits
        $archivedJobs{$jobID} and next;
        purgeStatusFileTarget($line[$statusFields{targetScript}]);
        my $logFiles = getLogFiles($qType, $line[$statusFields{jobName}], $jobID, $line[$statusFields{array}]);
        purgeStatusFileTarget(@$logFiles);
        #my $envFile = getEnvFile($qType, $jobID);
        #purgeStatusFileTarget($envFile);
    } 
    close $statusFileH;
    $purgeArchives and purgeStatusFileTarget(glob "$archiveStem.*");
}
sub purgeStatusFileTarget {
    my (@targetFiles) = @_;
    $options{'dry-run'} and return; 
    unlink @targetFiles; 
}
#========================================================================

1;

