use strict;
use warnings;

#========================================================================
# 'report.pl' returns the log files of queued jobs
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $logDir %allJobs %targetJobIDs $taskID $separatorLength);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qReport {  
    $options{'no-chain'} = 1;  # report action restricted to requested jobs
    getJobStatusInfo(); 
    parseJobOption(\%allJobs, 1, 1); 
    showLogs();   
} 
#========================================================================
     
#========================================================================
# echo log files
#------------------------------------------------------------------------
sub showLogs { 
    my @jobIDs = sort {$a <=> $b} keys %targetJobIDs;  
    if(@jobIDs){
        foreach my $jobID(@jobIDs){
            print "=" x $separatorLength, "\n";
            $options{'_q_remote_'} and print "LOG FILE: ";
            print defined $taskID ? "task: $jobID\[$taskID\]" : "job: $jobID", "\n";  
            my ($qType, $array, $inScript, $command, $instrsFile, $scriptFile, $jobName) = @{$targetJobIDs{$jobID}};    
            my $logFiles;
            if(defined $taskID){
                $logFiles = [ getArrayTaskLogFile($qType, $jobID, $taskID, $jobName) ];
            } else {
                $logFiles = getLogFiles($qType, $jobName, $jobID, $array);
            }
            foreach my $inFile (@$logFiles){ 
                -e $inFile or next;
                print "-" x $separatorLength, "\n"; 
                print "$inFile\n";
                print "-" x $separatorLength, "\n";  
                my $fileContents = slurpFile($inFile); 
                #---------------------------------------------------------------------------------
                # The following line removes the character sequence '<ESC>[H<ESC>[2J'
                # that SGE qsub (or something else?) adds to the end of log files.
                # The sequence is a "clear screen" escape sequence that messes up job reporting.
                $fileContents =~ s|\e\[H\e\[2J||g;  #\e is the escape character  
                #---------------------------------------------------------------------------------   
                print $fileContents;  
            }  
        }
        print "=" x $separatorLength, "\n";
    } else {
        print "no jobs matched '--job $options{'job'}'\n";
    }
}
#========================================================================
     
#========================================================================
# log files
#------------------------------------------------------------------------
sub getLogDir {
    my ($qType) = @_;
    return "$logDir/$qType";
}
sub getLogFiles {
    my ($qType, $jobName, $jobID, $array, $forceLogDir) = @_;
    my $useLogDir = $forceLogDir ? $forceLogDir : "$logDir/$qType";
    $jobName =~ s/\s+$//;
    if($array){
        my $arrayJobDelimiter = getArrayJobDelimiter($qType);
        my @logFiles;
        foreach my $taskID(split(",", $array)){  
            push @logFiles, "$useLogDir/$jobName.o$jobID$arrayJobDelimiter$taskID"
        }
        return \@logFiles;
    } else {
        return [ "$useLogDir/$jobName.o$jobID" ];
    }
}
sub getArrayTaskLogFile {
    my ($qType, $jobID, $taskID, $jobName) = @_;
    $jobName =~ s/\s+$//;
    my $arrayJobDelimiter = getArrayJobDelimiter($qType);
    return "$logDir/$qType/$jobName.o$jobID$arrayJobDelimiter$taskID";
}
sub getArrayJobDelimiter {
    my ($qType) = @_;
    if($qType eq 'SGE') {
        return ".";     
    } elsif($qType eq 'PBS' or $qType eq 'slurm') {
        return "-";
    } else {
        die "getArrayJobDelimiter error: array jobs are not allowed for qType 'local'\n";
    }
}
#========================================================================

1;

