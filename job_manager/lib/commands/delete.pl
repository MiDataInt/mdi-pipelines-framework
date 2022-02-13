use strict;
use warnings;

#========================================================================
# 'delete.pl' deletes incomplete jobs in last-in-first-out order within a dependency chain
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($qType $schedulerDir %options %jobIDs %successors %deletable $statusFile %statusFields);
our (@targetJobIDs, %targetJobIDs, $taskID);  # --job options parsing provided by delete.pl
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qDelete { # delete all incomplete jobs from queue
    #checkLock();
    updateStatusQuietly();
    parseJobOption(\%deletable, 'delete');  
    deleteTargetJobs();    
}
#========================================================================

#========================================================================
# find target jobIDs from option --job and successors
#------------------------------------------------------------------------
sub parseJobOption {  # determine --job format and parse into jobIDs, checking against allowed job list
    my ($allowedHash, $command) = @_;
    $options{'job'} or $options{'job'} = 'all'; # unsafe jobs required a value upstream of this call
    my $formatError = "unrecognized format for --job option:  $options{'job'}\n";
    if($options{'job'} eq 'all') {  
        @targetJobIDs = keys %$allowedHash;   
        $options{'no-chain'} = 1;  # no need to chain if already using all allowed jobs                        
    } elsif($options{'job'} =~ m|^(\d+)$|){  # single jobID
        $$allowedHash{$1} and @targetJobIDs = ($1);  
    } elsif($options{'job'} =~ m|^(\d+)\[(\d+)\]$|) {  # task of an array job
        $$allowedHash{$1} and @targetJobIDs = ($1) and $taskID = $2;
    } elsif($options{'job'} =~ m|^(\d+)\*$|) {  # terminal wild-card
        my $jobIDRef = $1;
        foreach my $jobID(keys %$allowedHash){ $jobID =~ m|^$jobIDRef| and push @targetJobIDs, $jobID }          
    } elsif($options{'job'} =~ m|^(\d+)\+$|) {  # greater than or equal to provided jobID
        my $jobIDRef = $1;
        foreach my $jobID(keys %$allowedHash){ $jobID >= $jobIDRef and push @targetJobIDs, $jobID }
    } elsif($options{'job'} =~ m|,|) {  
        foreach my $jobID(split(",", $options{'job'})){ 
            $jobID =~ m|^\d+$| or die $formatError;
            $$allowedHash{$jobID} and push @targetJobIDs, $jobID;
        }    
    } elsif($options{'job'} =~ m|^(\d+)-(\d+)$|) {  
        my ($start, $end) = ($1, $2);
        if($end < $start){
            my $beginDigits = length($start) - length($end);
            $beginDigits > 0 or die $formatError;
            $beginDigits = substr($start, 0, $beginDigits);
            $end = $beginDigits.$end;
        }
        for(my $jobID = $start; $jobID <= $end; $jobID++){
            $$allowedHash{$jobID} and push @targetJobIDs, $jobID;
        }     
    } else {
        die $formatError;
    }
    addSuccessorJobs($allowedHash);
}
sub addSuccessorJobs {  # extend the user provided list by descending into job dependency chains
    my ($allowedHash) = @_;
    foreach my $jobID(sort {$a <=> $b} @targetJobIDs){  # asc sort ensures that high-level jobs are checked first
        $targetJobIDs{$jobID} and next;  # job already encountered, therefore all of its successors have already been checked
        $targetJobIDs{$jobID} = $$allowedHash{$jobID};  # final hash contains same values as allowed hash
        $options{'no-chain'} and next;  # user instructed not to nest into job chains
        my ($submittedTime, $successorList) = @{$successors{$jobID}};       
        getRecursiveSuccessors($successorList, $jobIDs{$submittedTime}, $allowedHash); 
    }  
}
sub getRecursiveSuccessors {  # recursively find the successors of any successor jobs
    my ($successorList, $jobIDs, $allowedHash) = @_; 
    $successorList or return;
    foreach my $successor(split(",", $successorList)){
        my $jobID = $$jobIDs{$successor};  # convert successor job # to jobID
        $targetJobIDs{$jobID} = $$allowedHash{$jobID};
        my ($submittedTime, $successorList) = @{$successors{$jobID}};
        getRecursiveSuccessors($successorList, $jobIDs, $allowedHash);
    }
}
#========================================================================

#========================================================================
# execute job deletion
#------------------------------------------------------------------------
sub deleteTargetJobs { # delete all jobs in a list in LIFO order
    my @jobIDs = sort {$b <=> $a} keys %targetJobIDs; # desc sort ensures LIFO deletion 
    if(@jobIDs){
        if($options{'dry-run'}){
            print "the following jobs will be deleted:\n";
            showTargetJobs();
        } else {
            my $deleteMessage = "deleting incomplete jobs";
            $options{'force'} and print "$deleteMessage\n";
            getPermission($deleteMessage) or exit;
            my $delimiter = $qType eq "PBS" ? " " : ",";
            my $command   = $qType eq "slurm" ? "scancel" : "qdel";
            my $jobIDList = join ($delimiter, @jobIDs);
            system("$schedulerDir/$command $jobIDList 2>/dev/null");
            updateStatusFiles(\%targetJobIDs);
        }
    } else {
        print "all jobs matching '--job $options{'job'}' are complete or were previously deleted\n";
    }
}
sub showTargetJobs{  # show pretty-parse of jobs that were acted on when requested by by calling command
    my (@echoLines, %echoLines);
    open my $statusFileH, "<", $statusFile or return;
    while(my $line = <$statusFileH>){
        my @line = split("\t", $line);
        my $jobID = $line[$statusFields{jobID}];
        ($jobID and $targetJobIDs{$jobID}) or next;
        getStatusLine(\@echoLines, 1, "  ",
                        $line[$statusFields{jobName}],
                        $line[$statusFields{array}] ? '@' : ' ',                                    
                        $line[$statusFields{jobID}], 
                        $line[$statusFields{exit_status}], 
                        $line[$statusFields{start_time}], 
                        $line[$statusFields{walltime}], 
                        $line[$statusFields{maxvmem}],
                        $line[$statusFields{user}] );  
    }
    close $statusFileH;
    sortEchoLines(\@echoLines, \%echoLines);
    print join("\n", @echoLines),"\n";
}
#========================================================================

1;

