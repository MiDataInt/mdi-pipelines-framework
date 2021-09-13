use strict;
use warnings;

#========================================================================
# 'script.pl' returns the parsed target scripts of queued jobs
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $scriptDir %allJobs %targetJobIDs $separatorLength);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qScript {
    $options{'no-chain'} = 1;  # report action restricted to requested jobs  
    getJobStatusInfo();
    parseJobOption(\%allJobs, 'script');  
    showScripts();
} 
#========================================================================

#========================================================================
# echo parsed target scripts
#------------------------------------------------------------------------
sub showScripts { 
    my @jobIDs = sort {$a <=> $b} keys %targetJobIDs;
    if(@jobIDs){
        foreach my $jobID(@jobIDs){
            print "=" x $separatorLength, "\n";
            $options{'_q_remote_'} and print "SCRIPT: ";
            print "job: $jobID", "\n";      
            print "-" x $separatorLength, "\n"; 
            my ($qType, $array, $targetScript) = @{$targetJobIDs{$jobID}};  
            my $inFile = $targetScript;
            my $fileContents;
            if(-e $inFile){
                print "$inFile\n";                 
                print "-" x $separatorLength, "\n";           
                $fileContents = slurpFile($inFile);
            } else {
                $fileContents = "could not recover associated script file\n";
            }
            print $fileContents, "\n";            
        }
        print "=" x $separatorLength, "\n";
    } else {
        print "no jobs matched '--job $options{'job'}'\n";
    }
}
#========================================================================

#========================================================================
# script files
#------------------------------------------------------------------------
sub getScriptDir {
    my ($qType) = @_;
    return "$scriptDir/$qType";
}
#=======================================================================

1;

