use strict;
use warnings;

#========================================================================
# 'ssh.pl' executes an ssh command on the host/node running a live job
# if no command is provided, a shell is opened
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options %allJobs %targetJobIDs $taskID $pipelineOptions);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qSsh { 

    # initialize
    my $error = "command 'ssh' requires a single running job or task ID";
    my $tooManyJobs = "too many matching job targets\n$error";    
    $options{'no-chain'} = 1;  # ssh action restricted to requested jobs

    # get a single target job, or a single task of an array job
    getJobStatusInfo(); 
    parseJobOption(\%allJobs, 'ssh'); 
    my @jobIDs = keys %targetJobIDs; 
    @jobIDs == 1 or throwError($tooManyJobs, "ssh"); 
    my $jobID = $jobIDs[0];

    # get and check the job/task log file
    my ($qType, $array, $inScript, $command, $instrsFile, $scriptFile, $jobName) = @{$targetJobIDs{$jobID}};
    my $logFiles;
    if(defined $taskID){
        $logFiles = [ getArrayTaskLogFile($qType, $jobID, $taskID, $jobName) ];
    } else {
        $logFiles = getLogFiles($qType, $jobName, $jobID, $array);
    }
    @$logFiles == 1 or throwError($tooManyJobs, "ssh"); 
    my $logFile = @$logFiles[0];  
    -e $logFile or throwError("job log file not found\n$error", "ssh"); 

    # extract the job manager status reports from the job/task log file
    my $yamls = loadYamlFromString( slurpFile($logFile) );
    my %jmData;
    foreach my $yaml(@{$$yamls{parsed}}){
        my $jm = $$yaml{'job-manager'} or next;
        foreach my $key(keys %$jm){
            $jmData{$key} = $$jm{$key}[0]
        }
    }
    $jmData{exit_status} and throwError("job has exited\n$error", "ssh"); 

    # pass the call to system ssh
    my $host = $jmData{host};
    $host or throwError("error processing job log file: missing host", "ssh");     
    exec join(" ", "ssh -t $host", $pipelineOptions); # use -t (terminal) to support interactive commands like [h]top
}
#========================================================================

1;
