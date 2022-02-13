use strict;
use warnings;

#========================================================================
# 'ls.pl' lists the contents of the output directory of a specific job
# arguments are taken to be the sub-directory to ls; otherwise ls $TASK_DIR
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options %allJobs %targetJobIDs $taskID $pipelineOptions);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qLs { 

    # read required information from job log file
    my $mdiCommand = "ls";
    my $logFileYamls = getJobLogFileContents($mdiCommand);
    my $taskDir;
    foreach my $yaml(@$logFileYamls){
        my $action = $$yaml{'execute'} or next;
        my $outputDir = $$yaml{$$action[0]}{'output'}{'output-dir'}[0];
        my $dataName  = $$yaml{$$action[0]}{'output'}{'data-name'}[0];
        $taskDir = "$outputDir/$dataName";
    }

    # pass the call to system ls
    $taskDir or throwError("error processing job log file: could not extract the task directory", $mdiCommand);
    my $lsDir = join("/", $taskDir, $pipelineOptions);
    exec "echo $lsDir; ls -lah $lsDir"; 
}
#========================================================================

1;
