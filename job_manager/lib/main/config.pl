use strict;
use warnings;
use vars qw($jobManagerName);
my $jmName = $ENV{JOB_MANAGER_NAME} ? $ENV{JOB_MANAGER_NAME} : $jobManagerName;

#========================================================================
# configure job manager commands and options
#------------------------------------------------------------------------
# commands
#------------------------------------------------------------------------
our %commands = (  # [executionSub, commandHelp, mdiStage2]
    submit      =>  [\&qSubmit,      "queue all required data analysis jobs on the HPC server"],      
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
    initialize  =>  [undef,           "refresh the '$jmName' script to establish its program targets", 1], # 'mdi' handles this call
    install     =>  [\&mdiInstall,    "re-run the installation process to update suites, etc.", 1], # install and add assume a Stage 2 installation
    add         =>  [\&mdiAdd,        "add one tool suite repository to config/suites.yml and re-install", 1],
    list        =>  [\&mdiList,       "list all pipelines and apps available in this MDI installation", 1],
    build       =>  [\&mdiBuild,      "build one container with all of a suite's pipelines and apps", 1],
    server      =>  [\&mdiServer,     "launch the web server to use interactive Stage 2 apps",  1],
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
    'forks'=>              ["F", undef,   "install", 1, "also install your developer forks of MDI GitHub repositories"],
    'suite'=>              ["s", "<str>", "install", 2, "a single suite to install or build, in form GIT_USER/SUITE_NAME"],
    'version'=>            ["V", "<str>", "install", 3, "the version of the suite to build, e.g. v0.0.0 [latest]"],
    'sandbox'=>            ["S", undef,   "install", 4, "pass option '--sandbox' to singularity build"],
    'server-command'=>     ["c", "<str>", "server", 0, "command to launch the web server (run, develop, remote, node) [run]"],
    'data-dir'=>           ["D", "<str>", "server", 1, "path to the desired data directory [MDI_DIR/data]"],
    'host-dir'=>           ["H", "<str>", "server", 2, "path to a shared/public MDI installation with code and resources [MDI_DIR]"],
    'runtime'=>            ["m", "<str>", "server", 3, "execution environment: direct, container, or auto (container if supported) [auto]"],
    'container-version'=>  ["C", "<str>", "server", 4, "the major.minor version of either R or a tool suite, e.g., 4.1 [latest]"],
    'port' =>              ["P", "<int>", "server", 5, "the port that the server will listen on [3838]"],
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
    install    =>  {'install-packages'=>0, 'forks'=>0},
    add        =>  {'install-packages'=>0, 'suite'=>1},
    list       =>  {},
    build      =>  {'suite'=>1, 'version'=>0, 'sandbox' => 0},
    server     =>  {'server-command'=>0,'data-dir'=>0,'host-dir'=>0,'runtime'=>0,'container-version'=>0,'port'=>0}, 
);  
#========================================================================

1;
