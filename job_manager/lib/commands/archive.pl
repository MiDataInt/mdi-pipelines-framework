#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'archive.pl' saves a replicate of the current version of all status files
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options %statusFields $statusFile $archiveStem);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qArchive {  # allow user to create additional (non-automated) archives
    updateStatusQuietly();   
    archiveStatusFiles() or return;
    print "replicate of all updated status file has been saved\n",
          "use 'rollback' to revert to archived version\n";
}
#========================================================================

#========================================================================
# archive subroutines
#------------------------------------------------------------------------
sub archiveStatusFiles { 
    -e $statusFile or return;
    print "creating status file archive:\n";
    my $archiveNumber = getCurrentArchiveNumber();   
    $archiveNumber++;
    my $archiveFile = "$archiveStem.$archiveNumber";
    print "  $archiveFile\n";    
    qx/cp $statusFile $archiveFile/;
    return 1;
}
sub getCurrentArchiveNumber {  # get the highest numbered archive, i.e. the most recent archive
    my @archiveFiles = <$archiveStem.*>;
    my $archiveNumber = 0;
    foreach my $archiveFile(@archiveFiles){
        $archiveFile =~ m/$archiveStem.(\d+)$/ or next;
        $archiveNumber >= $1 or $archiveNumber = $1;
    }
    return $archiveNumber;
}
sub getArchivedJobs {  # get all jobs specified in archived status files
    my ($archivedJobs) = @_;
    my $archiveNumber = getCurrentArchiveNumber();   
    my $archiveFile = "$archiveStem.$archiveNumber";  # most recent archive always includes all jobs in older archives
    open my $statusFileH, "<", $archiveFile or die "could not open $archiveFile for reading: $!\n";
    while(my $line = <$statusFileH>){
        chomp $line;
        my @line = split("\t", $line);
        $line[0] or next;  
        my $jobID = $line[$statusFields{jobID}];
        $jobID and $jobID =~ m/^\d+$/ and $$archivedJobs{$jobID}++;  # job lines and only job lines have jobID field all digits
    } 
    close $statusFileH;
}
#========================================================================

#========================================================================
# show an archived status
#------------------------------------------------------------------------
sub showStatusArchive {
    -e $statusFile or return;
    my $archiveNumber = getCurrentArchiveNumber();
    my $archiveFile = "$archiveStem.$archiveNumber";
    if(-e $archiveFile){   
        print "showing archive: $archiveFile\n";    
        echoStatusFile($archiveFile);       
    } else {
        print "no archive for $statusFile\n";
    }
}
#========================================================================

1;

