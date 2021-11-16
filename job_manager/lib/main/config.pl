use strict;
use warnings;

#========================================================================
# configure job manager commands and options
#------------------------------------------------------------------------
# commands
#------------------------------------------------------------------------
our %commands = (  # [executionSub, commandHelp, mdiStage2]
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
#------------------------------------------------------------------------------------------------------------
    initialize  =>  [undef,           "refresh the 'mdi' command to establish its program targets", 1], # 'mdi' handles this call
    install     =>  [\&mdiInstall,    "re-run the MDI installation process to add new suites, etc.", 1],
    run         =>  [\&mdiRun,        "launch the MDI web server to use interactive Stage 2 apps",   1],

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
#------------------------------------------------------------------------------------------------------------
    'install-packages'=>   ["p", undef,   "install", 0, "install R packages required by Stage 2 Apps"],
    'develop'=>        ["v", undef,   "run", 0, "launch the web server in developer mode [run mode]"],
    'ondemand'=>       ["o", undef,   "run", 1, "launch the web server in ondemand mode [run mode]"],
    'data-dir'=>       ["D", "<str>",   "run", 2, "path to the desired data directory [./data]"],
    'host-dir'=>       ["H", "<str>",   "run", 3, "path to a shared/public MDI installation with code and resources [.]"],
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
    #move       =>  {'move-to'=>1,'force'=>0},
#------------------------------------------------------------------------------------------------------------
    initialize =>  {},
    install    =>  {'install-packages'=>0},
    run        =>  {'develop'=>0,'ondemand'=>0,'data-dir'=>0,'host-dir'=>0}, 
);  
#========================================================================

1;
