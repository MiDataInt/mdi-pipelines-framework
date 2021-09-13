#!/usr/bin/perl
use strict;
use warnings;

#========================================================================
# 'resubmit.pl' submits new identical copies of previously submitted jobs
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $masterDir $masterFileName  %extendable %allJobs %targetJobIDs $separatorLength
            $jobName $currentJob $array %jobPred %jobSucc $qsubOptions 
            $directives $qInUse $logDir %currentInstrsFile $currentScriptFile);
my (%newJobs, %newJobIDs);
my $queryMessage = "At least one job already exists in either the queued, running or completed state.\n".
                   "Continuing with 'q resubmit' will result in one or more duplicate identical jobs.";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qResubmit { 
    checkScheduler();
    checkLock();
    checkDeleteResubmit();
    checkSyntax('resubmit');
    %targetJobIDs = ();
    parseJobOption(\%allJobs, 'resubmit'); 
    $options{'_suppress-echo_'} or print "job_name                    array  job_ID   job_#  depends on job_#\n";
    resubmitJobs();
    provideFeedback();  
}
#========================================================================

#========================================================================
# resubmit jobs
#------------------------------------------------------------------------
sub checkDeleteResubmit {
    if($options{'delete'} and !$options{'_suppress-echo_'}){
        my $noChainHold = $options{'no-chain'};
        $options{'no-chain'} = undef;  # job deletion always applies to entire dependency chain 
        qDelete();
        $options{'no-chain'} = $noChainHold; # restore no-chain for subsequent resubmit
        print "~" x $separatorLength, "\n";
    } else {  
        updateStatusQuietly();
    } 
}
sub resubmitJobs {
    my @oldJobIDs = sort {$a <=> $b} keys %targetJobIDs;
    if(@oldJobIDs){
        getResubmitPermission(\@oldJobIDs);
        $qsubOptions = "-V";
        $qInUse and $qInUse eq 'SGE' and $qsubOptions .= " -terse"; # causes SGE to return only the job ID as output    
        $logDir = getLogDir($qInUse);
        foreach my $oldJobID(@oldJobIDs){
            my ($inQType, $inArray, $inScript, $command, $instrsFile, $scriptFile, $inJobName) = @{$targetJobIDs{$oldJobID}}; 
            $array = $inArray;
            $jobName = $inJobName;
            $currentInstrsFile{0} = $instrsFile;
            $currentScriptFile = $scriptFile;
            setEnvironment($inQType, $oldJobID);            
            $ENV{Q_LOG_DIR} = $logDir;
            $currentJob++;
            $newJobs{$oldJobID} = $currentJob;      
            @{$jobPred{$currentJob}} = ();                
            my $outScriptLines = parseResubmitScript($inScript);
            $options{'verbose'} and print "queueing job $jobName\n";
            my $outScript = writeOutScript($outScriptLines);
            my $newJobID = addJob($outScript, $command, ""); 
            $newJobIDs{$oldJobID} = $newJobID;       
        }
    } else {
        print "resubmit: no jobs matched '--job $options{'job'}'\n";
    }
}
sub getResubmitPermission {  # ensure permission to requeue known non-extendable jobs
    my ($oldJobIDs) = @_;
    $options{'dry-run'} and return;
    foreach my $oldJobID(@$oldJobIDs){
        unless($extendable{$oldJobID}){
            getPermission($queryMessage) and return 1;  
            print "'q resubmit' exiting\n";
            exit;
        }
    }
}
sub parseResubmitScript {
    my ($inScript) = @_;
    open my $inH, "<", $inScript or die "could not open $inScript for reading: $! \n";
    my ($haveDependencies, @newJobIDs, @outScriptLines, @directives);
    while (my $line = <$inH>){
        chomp $line;
        if($line =~ m|^(#PBS\s+-W\s+depend=afterok:)(\S+)|){  # PBS dependency line
            $line = replaceDependencies($1, $2, ":", $haveDependencies, \@newJobIDs);
            $haveDependencies = 1;
        } elsif($line =~ m|^(#\$\s+-hold_jid\s+)(\S+)|){  # SGE dependency line
            $line = replaceDependencies($1, $2, ",", $haveDependencies, \@newJobIDs); 
            $haveDependencies = 1; 
        }   
        push @outScriptLines, $line;        
        ($line =~ m/^#PBS/ or $line =~ m/^#\$/) and push @directives, $line;
    }
    close $inH; 
    $directives = join("\n", @directives)."\n";
    return \@outScriptLines;
}
sub replaceDependencies {
    my ($directive, $jobList, $delimiter, $haveDependencies, $newJobIDs) = @_;
    unless($haveDependencies){
        foreach my $oldJobID(split($delimiter, $jobList)){
            push @$newJobIDs, $newJobIDs{$oldJobID} ? $newJobIDs{$oldJobID} : $oldJobID;
            push @{$jobPred{$currentJob}}, $newJobs{$oldJobID} ? $newJobs{$oldJobID} : $oldJobID;
        }
        foreach my $job(@{$jobPred{$currentJob}}){
            $jobSucc{$job}{$currentJob}++; #track successors as reciprocal of predecessors
        }        
    }
    return $directive . join($delimiter, @$newJobIDs);
}
#========================================================================


1;

