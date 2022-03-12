use strict;
use warnings;
use Cwd(qw(abs_path));
			
#========================================================================
# 'main.pl' is the q command-line interpreter and help generator
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
# global program information
#------------------------------------------------------------------------
use vars qw($version $perlPath $bashPath $timePath $timeVersion 
            $memoryCorrection $memoryMessage $qDir $libDir $qType 
            $schedulerDir %shellCommands);         
my ($command, @args) = @ARGV;
my (@options, $makeDirs);
our ($masterFile, $masterDir, $masterFileName,
     $qDataDir, $archiveDir, $logDir, $scriptDir, 
     $envDir, $statusFile, $archiveStem);
#------------------------------------------------------------------------
# parsing of help feedback
#------------------------------------------------------------------------
my $commandTabLength = 12; 
my $optionTabLength = 20;
our $separatorLength = 87;
my @optionGroups = qw(main submit status job rollback lock auto protect publish move);  # ensure that similar options group together
my %useOptionGroupDelimiter = (submit=>1, extend=>1, resubmit=>1);  # break long options lists into separate groups
#------------------------------------------------------------------------
# q commands
#------------------------------------------------------------------------
my %allowedQTypes = (all=>[{0=>1,SGE=>1,PBS=>1}],  # not all commands apply to all job schedulers
                     sch=>[{SGE=>1,PBS=>1}, "requires either the SGE or PBS job schedulers"], 
                     SGE=>[{SGE=>1},        "does not apply to the PBS job scheduler"]);
my %commands = (  # [executionSub, allowedQTypes, commandHelp]
    submit      =>  [\&qSubmit,     $allowedQTypes{all}, "queue all jobs specified by the instructions in data_script"],      
    extend      =>  [\&qExtend,     $allowedQTypes{all}, "queue only new or deleted jobs specified by data_script"],   
    resubmit    =>  [\&qResubmit,   $allowedQTypes{sch}, "submit identical copies of jobs previously queued by data_script"],   
#------------------------------------------------------------------------------------------------------------
    status      =>  [\&qStatus,     $allowedQTypes{all}, "update and show the status of jobs queued by data_script"],
    report      =>  [\&qReport,     $allowedQTypes{all}, "show the log file of a job queued by data_script"],
    script      =>  [\&qScript,     $allowedQTypes{all}, "show the parsed target script for a job queued by data_script"],
    environment =>  [\&qEnvironment,$allowedQTypes{all}, "show the environment variables passed to a job queued by data_script"],
#------------------------------------------------------------------------------------------------------------
    clear       =>  [\&qClear,      $allowedQTypes{SGE}, "remove error states from jobs queued by data_script (SGE only)"], 
    delete      =>  [\&qDelete,     $allowedQTypes{sch}, "kill (qdel) incomplete jobs queued by data_script"],
#------------------------------------------------------------------------------------------------------------
    lock        =>  [\&qLock,       $allowedQTypes{all}, "set a protective marker that prevents job actions from data_script"],
    unlock      =>  [\&qUnlock,     $allowedQTypes{all}, "remove the protective marker set by 'q lock'"],    
    archive     =>  [\&qArchive,    $allowedQTypes{all}, "save a replicate of the current status file"], 
    rollback    =>  [\&qRollback,   $allowedQTypes{all}, "revert pipeline to the most recently archived status file"],
    purge       =>  [\&qPurge,      $allowedQTypes{all}, "remove all status, script and log files created by data_script"],   
    move        =>  [\&qMove,       $allowedQTypes{all}, "move/rename data_script and its associated q-generated derivative files"],
#------------------------------------------------------------------------------------------------------------
    protect     =>  [\&qProtect,    $allowedQTypes{all}, "write-protect (chmod a-w) files identified as 'protect <fileGlob>' in data_script"],
    unprotect   =>  [\&qUnprotect,  $allowedQTypes{all}, "remove file write-protection for --who (chmod <--who>+w)"],
    backup      =>  [\&qBackup,     $allowedQTypes{all}, "create a copy of directories identified as 'backup <directory>' in data_script"],
    restore     =>  [\&qRestore,    $allowedQTypes{all}, "restore from backup directories identified as 'backup <directory>' in data_script"],
#------------------------------------------------------------------------------------------------------------
    publish     =>  [\&qPublish,    $allowedQTypes{all}, "create a distribution of instruction, script, status, and log files"], 
); 
#------------------------------------------------------------------------
# q options
#------------------------------------------------------------------------
our %options; # collects the actual options specified by user on command line
our %optionInfo = (# [shortOption, valueString, optionGroup, groupOrder, optionHelp]          
    'version'=>     ["v", undef,   "main",    0, "report the q version"],
    'help'=>        ["h", undef,   "main",    1, "show program help"],   
#------------------------------------------------------------------------------------------------------------
    'dry-run'=>     ["d", undef,   "submit",  0, "check syntax and report actions to be taken; nothing will be queued or deleted"], 
    'depend'=>      ["D", "<str>", "submit",  1, "comma-delimited list of jobIDs upon which all new jobs should depend"], 
    'delete'=>      ["x", undef,   "submit",  2, "kill matching pending/running jobs when repeat job submissions are encountered"],    
    'execute'=>     ["e", undef,   "submit",  3, "run target jobs immediately in shell instead of submitting with qsub"],   
    'force'=>       ["f", undef,   "submit",  4, "suppress warnings that duplicate jobs will be queued, files deleted, etc."],  
    'verbose'=>     ["V", undef,   "submit",  5, "report all commands acted on from data_script (extremely verbose)"],    
#------------------------------------------------------------------------------------------------------------
    'archive'=>     ["a", undef,   "status",  0, "show the most recent archive instead of the current status"], 
    'no-update'=>   ["u", undef,   "status",  1, "suppress the status update, just show the most recently recorded status"],   
    'chain'=>       ["c", undef,   "status",  2, "show the job dependency chain instead of start/wall times and memory usage"], 
    'filter'=>      ["F", "<str>", "status",  3, "comma-delimited list of status filters: <column><operator><value>[, ... ]"],
    'sort'=>        ["S", "<str>", "status",  4, "column by which status lines should be sorted: <column>[:<order>]\n".
                        "                          columns:  user, job_name, job_ID, exit_status, start_time, wall_time, maxvmem\n".
                        "                          operators:  =, !=, ~, !~, >, <  (hint: quote or escape \!, \> and \<)\n".
                        "                          orders:  asc, desc"],                       
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
    'no-chain'=>    ["n", undef,   "job",     1, "only apply command to --job; do not apply to jobs dependent on --job"],      
#------------------------------------------------------------------------------------------------------------  
    'count'=>       ["N", "<int>", "rollback",0, "number of sequential rollbacks to perform [1]"],  
#------------------------------------------------------------------------------------------------------------  
    'lock'=>        ["K", undef,   "auto",    0, "automatically lock data_script after queuing jobs from it"],  
    'publish'=>     ["H", undef,   "auto",    1, "automatically add 'q publish' job after data_script jobs are queued"],
#------------------------------------------------------------------------------------------------------------
    'quiet'=>       ["q", undef,   "protect", 0, "do not show the names of files being (un)protected, backed up or restored"],    
    'who'=>         ["w", "<str>", "protect", 1, "list of classes to unprotect, consistent with chmod <--who>+w (e.g. a, u, or g)"],
#------------------------------------------------------------------------------------------------------------
    'long'=>        ["l", undef,   "publish", 0, "include jobID and start time information when publishing"],
    'mask'=>        ["m", "<str>", "publish", 1, "comma-delimited list of strings to mask when publishing"], 
    'title'=>       ["t", "<str>", "publish", 2, "title of the published html report (overridden by 'publishTitle' instructions)"],
    'intro-file'=>  ["i", "<str>", "publish", 3, "html overview to include when publishing (overridden by 'publishIntro' instructions)"],
    'out-dir'=>     ["o", "<str>", "publish", 4, "publish output directory (overridden by 'publishDir' instructions)"],
    'zip'=>         ["z", undef,   "publish", 5, "create a tarball (.tar.gz) of the publication report"],
#------------------------------------------------------------------------------------------------------------
    'move-to'=>     ["M", "<str>", "move",    1, "the file or directory to which data_script will be moved"],
#------------------------------------------------------------------------------------------------------------
    '_suppress-echo_'=>["NA", undef,   "NA", "NA", 0, "internalOption"], 
    '_extending_'=>    ["NA", undef,   "NA", "NA", 0, "internalOption"], 
    '_q_remote_'=>     ["NA", undef,   "NA", "NA", 0, "internalOption"], 
    '_server_mode_'=>  ["NA", undef,   "NA", "NA", 0, "internalOption"], 
);    
my %longOptions = map { ${$optionInfo{$_}}[0] => $_ } keys %optionInfo; # for converting short options to long; long options are used internally
#------------------------------------------------------------------------
# associate commands with allowed and required options
#------------------------------------------------------------------------
our %commandOptions =  ( # 0=allowed, 1=required
    submit     =>  {'dry-run'=>0,'execute'=>0,'depend'=>0,'delete'=>0,'force'=>0,'verbose'=>0,
                    'lock'=>0,'publish'=>0,'out-dir'=>0,'mask'=>0,'title'=>0,'long'=>0,'intro-file'=>0,    
                    '_suppress-echo_'=>0,'_extending_'=>0},
    extend     =>  {'dry-run'=>0,'execute'=>0,'depend'=>0,'delete'=>0,'force'=>0,'verbose'=>0,
                    'lock'=>0,'publish'=>0,'out-dir'=>0,'mask'=>0,'title'=>0,'long'=>0,'intro-file'=>0},   
    resubmit   =>  {'dry-run'=>0,'execute'=>0,'depend'=>0,'delete'=>0,'force'=>0,
                    'lock'=>0,'publish'=>0,'out-dir'=>0,'mask'=>0,'title'=>0,'long'=>0,'intro-file'=>0,    
                    'job'=>1,'no-chain'=>0,
                    '_suppress-echo_'=>0},  
#------------------------------------------------------------------------------------------------------------             
    status     =>  {'archive'=>0,'no-update'=>0,'chain'=>0,'filter'=>0,'sort'=>0},
    report     =>  {'job'=>1},
    script     =>  {'job'=>1},   
    environment=>  {'job'=>1},   
#------------------------------------------------------------------------------------------------------------
    clear      =>  {'dry-run'=>0,'job'=>1},
    delete     =>  {'dry-run'=>0,'job'=>1,'force'=>0}, 
#------------------------------------------------------------------------------------------------------------
    lock       =>  {},
    unlock     =>  {},
    archive    =>  {},
    rollback   =>  {'dry-run'=>0,'force'=>0,'count'=>0}, 
    purge      =>  {'dry-run'=>0,'force'=>0}, 
#------------------------------------------------------------------------------------------------------------
    protect    =>  {'dry-run'=>0,'quiet'=>0}, 
    unprotect  =>  {'dry-run'=>0,'quiet'=>0,'who'=>1},
    backup     =>  {'dry-run'=>0,'quiet'=>0},
    restore    =>  {'dry-run'=>0,'quiet'=>0,'force'=>0},   
#------------------------------------------------------------------------------------------------------------
    publish    =>  {'out-dir'=>0,'mask'=>0,'title'=>0,'long'=>0,'intro-file'=>0,'zip'=>0},
#------------------------------------------------------------------------------------------------------------
    move       =>  {'move-to'=>1,'force'=>0},
);  
foreach my $key(keys %commandOptions){  # enable _q_remote_ for all commands
    $commandOptions{$key}{'_q_remote_'} = 0;
    $commandOptions{$key}{'_server_mode_'} = 0;   
}
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qMain { 
    checkCommand();  # provide extensive syntax checking to prevent dangerous malformed commands
    my @masterFiles = setOptions();
    my $nMasterFiles = @masterFiles;
    if ($nMasterFiles == 1){
        ($masterFile) = @masterFiles;
    } elsif ($nMasterFiles > 1){ # re-run q for every masterFile provided
        my $options = join(" ", @options);
        foreach $masterFile (@masterFiles){ 
            system("perl $0 $command $options $masterFile") and exit 1;  # abort if any run dies
        }
        exit;
    } 
    checkRequiredOptions();
    checkMasterFile(); 
    executeCommand();  # request is valid, proceed with execution
}
#========================================================================

#========================================================================
# system utility subroutines
#------------------------------------------------------------------------
sub isShellCommand { # boolean indicating whether a command in known to host
    my ($shellCommand) = @_;
    exists $shellCommands{$shellCommand} or 
        $shellCommands{$shellCommand} = !system($bashPath, "-c", "which $shellCommand &> /dev/null");
    return $shellCommands{$shellCommand};
}
#------------------------------------------------------------------------
sub slurpFile {  # read the entire contents of a disk file into memory
    my ($file) = @_;
    local $/ = undef; 
    open my $inH, "<", $file or die "could not open $file for reading: $!\n";
    my $contents = <$inH>; 
    close $inH;
    return $contents;
}
#------------------------------------------------------------------------
sub getTime { # status update times
    my ($sec, $min, $hr, $day, $month, $year) = localtime(time);
    $year = $year + 1900;
    $month++;
    return "$month/$day/$year $hr:$min:$sec";
}
#------------------------------------------------------------------------
sub getPermission {  # get permission for jobs that will duplicate a job or delete/overwrite a file
    my ($queryMessage, $noForceUpdate) = @_;
    $options{'force'} and return 1;  # user has already given permission at command line
    print "\nWARNING!\n".
          "$queryMessage\n";
    if($options{'_q_remote_'}){
        print "\nCheck option 'force' to bypass this message.\n";
        exit;
    } else {
        print "continue? <yes or no>:  ";
        my $permission = <STDIN>;
        chomp $permission;
        $permission = "\U$permission";
        ($permission eq 'YES' or $permission eq 'Y') or return undef;
        $noForceUpdate or $options{'force'} = 1;  # granting permission is synonymous with setting --force
        return 1;    
    }    
}
#========================================================================

#========================================================================
# execution subroutines
#-----------------------------------------------------------------------
sub checkCommand { # check for help request or validity of requested command
    my $versionString = "q version $version\n";
    my $descriptionString = $versionString."q is a utility for submitting, monitoring and managing data analysis pipelines";
    $command or reportUsage($descriptionString);
    ($command eq '-v' or $command eq '--version') and print $versionString and exit;     
    ($command eq '-h' or $command eq '--help') and reportUsage("$descriptionString\n", "all");  
    $commands{$command} or reportUsage("\n'$command' is not a valid q command\n", "all", 1); 
    my ($allowedQTypes, $errorMessage) = @{${$commands{$command}}[1]};
    $$allowedQTypes{$qType} or reportUsage("\ncommand '$command' $errorMessage\n", "all", 1); 
}
#-----------------------------------------------------------------------
sub setOptions { # parse and check validity of options string
    while (my $optionList = shift @args){
        ($optionList and $optionList =~ m/^\-/) or return ($optionList, @args); # last item(s) in list should be masterFile(s)
        push @options, $optionList;    
        if($optionList =~ m/^\-\-(.+)/){ # long option formatted request
            my $longOption = $1;
            defined $optionInfo{$longOption} or reportUsage("'$longOption' is not a recognized q option", undef, 1); 
            setOption($longOption);
        } elsif ($optionList =~ m/^\-(.+)/){ # short option formatted request
            foreach my $shortOption(split('', $1)){
                my $longOption = $longOptions{$shortOption};
                defined $longOption or reportUsage("'$shortOption' is not a recognized q option", undef, 1);  
                setOption($longOption);
            }
        } else {
            reportUsage("malformed option list", undef, 1); 
        }
    }
    return undef;
}           
sub setOption { # check and set option request                
    my ($longOption) = @_;
    $longOption eq 'version' and print "q version $version\n" and exit;   
    $longOption eq 'help' and reportUsage("q version $version\n", $command); 
    defined ${$commandOptions{$command}}{$longOption} or reportUsage("\n'$longOption' is not a valid option for command '$command'\n", $command, 1);
    my $value; # boolean options set to value 1, otherwise use supplied value
    if(${$optionInfo{$longOption}}[1]){
        $value = shift @args;
        push @options, $value;    
    } else {
        $value = 1;
    }
    defined $value or reportUsage("\nmissing value for option '$longOption'\n", $command, 1);
    $value =~ m/^\-/ and reportUsage("\nmissing value for option '$longOption'\n", $command, 1);    
    $options{$longOption} = $value;  
}
sub checkRequiredOptions { # make sure required value options have been supplied
    foreach my $longOption (keys %{$commandOptions{$command}}){
        ${$commandOptions{$command}}{$longOption} or next; # option is not required
        defined $options{$longOption} or reportUsage("\noption '$longOption' is required for command '$command'\n", $command, 1);
    }
}
#-----------------------------------------------------------------------
sub checkMasterFile { # make sure master instructions file was specified and exists
    $masterFile or reportUsage("data_script not specified", undef, 1);
    !(-e $masterFile) and $masterFile eq 'q_example.q' and $masterFile = "$qDir/example/q_example.q";
    -e $masterFile or reportUsage("could not find data_script $masterFile", undef, 1);
    $masterFile = abs_path($masterFile);  # convert all relative paths to completes master paths
    $masterFile =~ m|(.*)/(.+)$| or die "error parsing data_script\n"; 
    ($masterDir, $masterFileName) = ($1, $2);
    $qDataDir = "$masterDir/.$masterFileName.data";  # q data for masterFile stored in single, portable hidden directory  
    $makeDirs = !(-d $qDataDir);
    $makeDirs and mkdir $qDataDir; 
    $archiveDir = getQSubDir('archive');
    $logDir = getQSubDir('log', 1);
    $scriptDir = getQSubDir('script', 1);
    $envDir = getQSubDir('environment', 1);
    $statusFile = "$qDataDir/$masterFileName.status";  # status file lives in top-level hidden directory
    $archiveStem = "$archiveDir/$masterFileName.status";
}
sub getQSubDir {  # subdirectories hold specific q-generated files
    my ($dirName, $makeSubDirs) = @_;
    my $dir = "$qDataDir/$dirName";
    $makeDirs and mkdir $dir;
    if($makeDirs and $makeSubDirs){  # job-level files placed into further subdirectories by qType
        foreach my $qType(qw(PBS SGE local)){
            my $qTypeDir = "$dir/$qType";
            -d $qTypeDir or mkdir $qTypeDir;
        }
    }
    return $dir;
}
#-----------------------------------------------------------------------
sub executeCommand { # load q scripts and execute command
    # TODO: marginal speed optimization will load only scripts required for a command
    $options{'_q_remote_'} and $options{'_server_mode_'} and require "$qDir/remote/def_env.pl";    
    foreach my $scriptName(qw(  submit
                                status
                                report
                                script
                                environment
                                delete
                                clear
                                resubmit
                                extend  
                                archive
                                rollback
                                lock
                                purge
                                move
                                protect
                                backup
                                publish )){
        my $script = "$libDir/$scriptName.pl";     
        require $script;
    }
    $options{'_suppress-echo_'} or print "~" x $separatorLength, "\n";
    &{${$commands{$command}}[0]}(@args);  # add remaining @args since other subs recall q with additional arguments
    $options{'lock'} and !$options{'dry-run'} and qLock();  # implement --lock option at submission time
    print "~" x $separatorLength, "\n";
}
#========================================================================

#========================================================================
# provide help feedback on command line
#------------------------------------------------------------------------
sub reportUsage { 
    my ($message, $command, $die) = @_;
    $message and print "$message\n";  
    print "usage:\tq <command> [options] <data_script> [...]\n",   
          "data_script = path to a top-level q instructions file specifying data targets\n";
    if($command){
        if($commands{$command}){ # help for options for known command
            reportOptionHelp($command);
        } else { # help on the set of available commands, organized by topic
            print "\navailable commands (use 'q <command> --help' for command options):\n\n";
            reportCommandChunk("job submission",              qw(submit extend resubmit));  
            reportCommandChunk("status and result reporting", qw(status report script environment));   
            reportCommandChunk("error handling",              qw(clear delete));
            reportCommandChunk("output management",           qw(protect unprotect backup restore));             
            reportCommandChunk("pipeline management",         qw(lock unlock archive rollback purge move));
            reportCommandChunk("pipeline distribution",       qw(publish));      
        }
    } else {
        print "use 'q --help' or 'q <command> --help' for extended help\n", 
    }   
    my $exitStatus = $die ? 1 : 0;
    exit $exitStatus; 
}
sub reportOptionHelp { 
    my ($command) = @_;
    print "\n";
    print getCommandLine($command);
    print "\n";
    print "available options:\n";
    my @availableOptions = sort {$a cmp $b} keys %{$commandOptions{$command}};
    if(@availableOptions){
        my %parsedOptions;
        foreach my $longOption(@availableOptions){
            my ($shortOption, $valueString, $optionGroup, $groupOrder, $optionHelp, $internalOption) = @{$optionInfo{$longOption}};
            $internalOption and next; # no help for internal options           
            my $option = "-$shortOption,--$longOption";
            $valueString and $option .= " $valueString";
            ${$commandOptions{$command}}{$longOption} and $optionHelp = "**REQUIRED** $optionHelp";
            $parsedOptions{$optionGroup}{$groupOrder} = "    $option".(" " x ($optionTabLength - length($option)))."$optionHelp\n";
        }
        my $delimiter = "";
        foreach my $optionGroup(@optionGroups){
            $parsedOptions{$optionGroup} or next;
            $useOptionGroupDelimiter{$command} and print "$delimiter";              
            foreach my $groupOrder(sort {$a <=> $b} keys %{$parsedOptions{$optionGroup}}){
                print $parsedOptions{$optionGroup}{$groupOrder};   
            }         
            $delimiter = "\n";
        }
    } else {
        print "    none\n";
    }
    print "\n";
}
sub reportCommandChunk {
    my ($header, @commands) = @_;
    print "  $header:\n";
    foreach my $command (@commands){
        print "    ", getCommandLine($command);
    }
    print "\n";
}
sub getCommandLine {
    my ($command) = @_;
    return $command, " " x ($commandTabLength - length($command)), ${$commands{$command}}[2], "\n";
}
#========================================================================

1;

