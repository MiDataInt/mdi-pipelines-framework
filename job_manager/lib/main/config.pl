use strict;
use warnings;

#========================================================================
# configure job manager commands and options
#------------------------------------------------------------------------
# commands
#------------------------------------------------------------------------
our %commands = (  # [executionSub, commandHelp]
    submit      =>  [\&qSubmit,      "queue all required data analysis jobs on the server"],      
    extend      =>  [\&qExtend,      "queue only new or deleted/unsatisfied jobs"],   
#------------------------------------------------------------------------------------------------------------
    status      =>  [\&qStatus,      "show the updated status of previously queued jobs"],
    report      =>  [\&qReport,      "show the log file of a previously queued job"],
    script      =>  [\&qScript,      "show the parsed target script for a previously queued job"],
#------------------------------------------------------------------------------------------------------------
    delete      =>  [\&qDelete,      "kill jobs that have not yet finished running"],
#------------------------------------------------------------------------------------------------------------
    rollback    =>  [\&qRollback,    "revert pipeline to the most recently archived status file"],
    purge       =>  [\&qPurge,       "remove all status, script and log files associated with the jobs"],
    #move        =>  [\&qMove,        "move/rename <data.yml> and its associated script and status files"],
); 
#------------------------------------------------------------------------
# options
#------------------------------------------------------------------------
our %optionInfo = (# [shortOption, valueString, optionGroup, groupOrder, optionHelp]          
    'help'=>        ["h", undef,   "main",    1, "show program help"],   
#------------------------------------------------------------------------------------------------------------
    'dry-run'=>     ["d", undef,   "submit",  0, "check syntax and report actions to be taken; nothing will be queued or deleted"], 
    'delete'=>      ["x", undef,   "submit",  2, "kill matching pending/running jobs when repeat job submissions are encountered"],    
    'execute'=>     ["e", undef,   "submit",  3, "run target jobs immediately in the shell instead of scheduling them"],   
    'force'=>       ["f", undef,   "submit",  4, "suppress warnings that duplicate jobs will be queued, files deleted, etc."],  
#------------------------------------------------------------------------------------------------------------   
    'job'=>         ["j", "<str>", "job",     0, "restrict command to specific jobID(s) (and sometimes its successors)\n". 
                        "                          allowed formats for <str>:\n".
                        "                            <int>         one specific jobID\n".
                        "                            <int>[<int>]  one specific task of an array job, e.g. 6789[2]\n".
                        "                            <int>*        all jobIDs starting with <int>\n".
                        "                            <int>-<int>   a range of jobsIDs\n".
                        "                            <int>+        all jobIDS greater than or equal to <int>\n".
                        "                            <int>, ...    comma-delimited list of jobIDs\n".                      
                        "                            all           all known jobIDs"],
#------------------------------------------------------------------------------------------------------------  
    'count'=>       ["N", "<int>", "rollback",0, "number of sequential rollbacks to perform [1]"],
#------------------------------------------------------------------------------------------------------------
    #'move-to'=>     ["M", "<str>", "move",    1, "the file or directory to which <data.yml> will be moved"],
#------------------------------------------------------------------------------------------------------------
    '_suppress-echo_'=>["NA", undef,   "NA", "NA", 0, "internalOption"], 
    '_extending_'=>    ["NA", undef,   "NA", "NA", 0, "internalOption"], 
    '_q_remote_'=>     ["NA", undef,   "NA", "NA", 0, "internalOption"], 
    '_server_mode_'=>  ["NA", undef,   "NA", "NA", 0, "internalOption"], 
);
our %longOptions = map { ${$optionInfo{$_}}[0] => $_ } keys %optionInfo; # for converting short options to long; long options are used internally
#------------------------------------------------------------------------
# associate commands with allowed and required options
#------------------------------------------------------------------------
our %commandOptions =  ( # 0=allowed, 1=required
    submit     =>  {'dry-run'=>0,'delete'=>0,'execute'=>0,'force'=>0,
                    '_suppress-echo_'=>0,'_extending_'=>0},
    extend     =>  {'dry-run'=>0,'delete'=>0,'execute'=>0,'force'=>0},   
#------------------------------------------------------------------------------------------------------------             
    status     =>  {},
    report     =>  {'job'=>1},
    script     =>  {'job'=>1},   
#------------------------------------------------------------------------------------------------------------
    delete     =>  {'dry-run'=>0,'job'=>1,'force'=>0}, 
#------------------------------------------------------------------------------------------------------------
    rollback   =>  {'dry-run'=>0,'force'=>0,'count'=>0}, 
    purge      =>  {'dry-run'=>0,'force'=>0},
    #move       =>  {'move-to'=>1,'force'=>0}
);  
#========================================================================

1;

