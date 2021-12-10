use strict;
use warnings;

#========================================================================
# 'status.pl' updates and shows status files
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $statusFile $archiveStem $archiveDir $qType 
            $schedulerDir $memoryCorrection $masterFileName);
our %statusFields = (  # column format of status files
    jobName=>0,        # text name of the job as provided by user and/or assembled by q; space-padded to 30-char length
    jobID=>1,          # the jobID as assigned by qsub, or the same as 'job' if --execute was in force
    array=>2,          # comma-delimited list of array task IDs, empty if not an array job
    job=>3,            # a job id used internally for job dependency tracking; numbering starts at 1
    predecessors=>4,   # comma-delimited list of jobs on which this job depended; values are as 'job', not 'jobID'
    successors=>5,     # comma-delimited list of jobs that depended on this job; values are as 'job', not 'jobID'
    start_time=>6,     # clock time when the job started (or when the first job of an array started)
    exit_status=>7,    # status of the job as reported by qstat and later the exit status of the job
    walltime=>8,       # elapsed time it took the job to run (or max time of all array jobs) as reported by /usr/bin/time
    maxvmem=>9,        # maxvmem (or max maxvmem of all array jobs) as reported by qstat and later by /usr/bin/time
    targetScript=>10,  # the path to the parsed execution script that was actually submitting for running
    command=>11,       # condensed version of the execution config; used for identifying equivalent jobs
    instrsFile=>12,    # DEPRECATED, UNUSED; was used by publish
    scriptFile=>13,    # DEPRECATED, UNUSED; was used by publish
    user=>14,          # the system user who queued the job
    qType=>15          # scheduler that queued the job, used to parse file names; could be 'local', i.e. different than qType
);           
our (%jobIDs, %successors, %deletable, %inError, %exists, %extendable, %allJobs);
my @filterOperators = qw(= != ~ !~ > <);  # status filtering by equality or string matching
my @outputColumns = qw (job_name array job_ID exit_status start_time wall_time maxvmem job predecessors user);
my $i = 0;
my %outputColumns = map { $_ => $i++ } @outputColumns;  
my @keepInEcho = $options{'chain'} ? (0..3, 7, 8) : (0..6); 
my %numericFilterSort = (job_name=>0,array=>0,job_ID=>1,exit_status=>0,start_time=>1,wall_time=>1,maxvmem=>1,user=>0,job=>1,predecessors=>0);
my %sortColumns = (job_name=>'jobName',array=>'array',job_ID=>'jobID',exit_status=>'exit_status',  # added to avoid renaming statusFields in file
                   start_time=>'start_time',wall_time=>'walltime',maxvmem=>'maxvmem',user=>'user',
                   job=>'job',predecessors=>'predecessors');  
my (@statusFilters, $sortColumn, $sortOrder, $sortIndex);      
my $exitWidth = $options{'chain'} ? 11 : 3;
my %columnWidths = (job_name=>30,array=>1,job_ID=>9,exit_status=>$exitWidth,start_time=>18,wall_time=>9,maxvmem=>7,job=>4,predecessors=>24);  
my %padChars = (job_name=>'-',array=>' ',job_ID=>' ',exit_status=>' ',start_time=>' ',wall_time=>' ',maxvmem=>' ',job=>' ',predecessors=>' ');  
my %emptyChars = (job_name=>'-',array=>' ',job_ID=>' ',exit_status=>'-',start_time=>'-',wall_time=>'-',maxvmem=>'-',job=>' ',predecessors=>' ');  
my @statusHeaders = (
    'job_name                  ',
    'array',                
    'job_ID   ', # extra spaces added intentionally for table parsing
    'exit_status',
);
push @statusHeaders, $options{'chain'} ? (
    'job ',
    'predecessors'
) : (
    'start_time',
    'wall_time',
    'maxvmem' 
);
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qStatus { # update and report the status of jobs queued by masterFile
    checkSortColumn();    
    parseStatusFilters(); 
    if($options{'archive'}){
        showStatusArchive();
    } elsif($options{'no-update'}) {
        my $warning = "!!! job statuses may not be current !!!\n";
        print $warning;
        echoStatusFile($statusFile);  
        print $warning;     
    } else {
        updateStatusFiles();
    }   
}
#========================================================================

#========================================================================
# update and return job statuses
#------------------------------------------------------------------------
sub updateStatusQuietly {
    my ($justDeleted) = @_; 
    my $suppressEchoHold = $options{'_suppress-echo_'}; 
    $options{'_suppress-echo_'} = 1;
    updateStatusFiles($justDeleted);
    $options{'_suppress-echo_'} = $suppressEchoHold;
}
sub updateStatusFiles { # update the job status of all jobIDs found in report files and collect various job information
    my ($justDeleted) = @_; 
    %jobIDs = (); 
    %successors = ();
    %deletable = ();
    %inError = ();
    %exists = ();
    %extendable = ();
    %allJobs = ();
    getJobStates(\my%jobStates);
    open my $statusFileH, "<", $statusFile or return;
    $options{'_q_remote_'} or print "updating $statusFile\n";              
    my (@fileLines, @echoLines, %echoLines);
    my $time = "updated\t".getTime(); # change updated time to current
    push @fileLines, $time;
    $options{'sort'} or push @echoLines, $time;
    my $submittedTime;
    while(my $line = <$statusFileH>){
        chomp $line;
        my @line = split("\t", $line);
        $line[0] or next;
        if($line[0] =~ m/updated/){
            # do nothing to lose any old status update time
        } elsif ($line[$statusFields{jobID}] =~ m/^\d+$/) {# job lines and only job lines have jobID field all digits
            my $jobName = $line[$statusFields{jobName}];
            my $jobID = $line[$statusFields{jobID}];
            my $exitStatus = $line[$statusFields{exit_status}];
            my $command = $line[$statusFields{command}];
            if(defined $exitStatus and ($exitStatus =~ m/^\d+$/ or $exitStatus =~ m/deleted/)){# jobs that don't need a status update
                push @fileLines, join("\t", @line);  # pass all finalized job entries
                my $echoArray = getEchoArray(\@echoLines, \%echoLines, \@line);
                getStatusLine($echoArray, 1, "  ",
                                $line[$statusFields{jobName}],
                                $line[$statusFields{array}] ? '@' : ' ',                                    
                                $line[$statusFields{jobID}], 
                                $line[$statusFields{exit_status}], 
                                $line[$statusFields{start_time}], 
                                $line[$statusFields{walltime}], 
                                $line[$statusFields{maxvmem}],
                                $line[$statusFields{job}], 
                                $line[$statusFields{predecessors}],                                 
                                $line[$statusFields{user}] );                       
            } else { # jobs whose status potentially needs updating
                getJobStatus($jobName, $jobID, \%jobStates, \my%jobInfo, $justDeleted, $line[$statusFields{array}], $line[$statusFields{qType}]);
                $exitStatus = $jobInfo{exit_status};
                getStatusLine(\@fileLines, 0, "\t",
                                $line[$statusFields{jobName}],
                                $line[$statusFields{jobID}], 
                                $line[$statusFields{array}], 
                                $line[$statusFields{job}], 
                                $line[$statusFields{predecessors}], 
                                $line[$statusFields{successors}], 
                                $jobInfo{start_time},
                                $jobInfo{exit_status},
                                $jobInfo{walltime},   
                                $jobInfo{maxvmem},   
                                $line[$statusFields{targetScript}], 
                                $line[$statusFields{command}],
                                $line[$statusFields{instrsFile}],
                                $line[$statusFields{scriptFile}],
                                $line[$statusFields{user}],
                                $line[$statusFields{qType}] );
                my $echoArray = getEchoArray(\@echoLines, \%echoLines, \@line);
                getStatusLine($echoArray, 1, "  ",
                                $line[$statusFields{jobName}],
                                $line[$statusFields{array}] ? '@' : ' ',                                    
                                $line[$statusFields{jobID}], 
                                $jobInfo{exit_status}, 
                                $jobInfo{start_time}, 
                                $jobInfo{walltime}, 
                                $jobInfo{maxvmem},
                                $line[$statusFields{job}], 
                                $line[$statusFields{predecessors}],                                 
                                $line[$statusFields{user}] );                                 
            }
            $jobIDs{$submittedTime}{$line[$statusFields{job}]} = $jobID;
            $successors{$jobID} = [$submittedTime, $line[$statusFields{successors}]];
            $exists{$command}++;
            delete $extendable{$command}; # use only the most recent extendability information for a given command
            if(defined $exitStatus){
                !($exitStatus =~ m/^\d+$/ or $exitStatus =~ m/deleted/) and $deletable{$jobID} = $exitStatus;
                $exitStatus eq 'Eqw' and $inError{$jobID}++;
                ($exitStatus =~ m/deleted/ or $exitStatus eq "137") and $extendable{$command}++ and $extendable{$jobID}++;
            } else {
                $extendable{$command}++;
            } 
            $allJobs{$jobID} = [$line[$statusFields{qType}], $line[$statusFields{array}], $line[$statusFields{targetScript}],
                                $line[$statusFields{command}], $line[$statusFields{instrsFile}], $line[$statusFields{scriptFile}],
                                $line[$statusFields{jobName}]];
        } elsif ($line[0] eq 'submitted') {# collect submission grouping for dependency tracking
            $submittedTime = $line[1];
            push @fileLines, $line; 
            $options{'sort'} or push @echoLines, $line;
        } elsif ($line[0] eq 'jobName') {# replace header line on echo
            push @fileLines, $line; 
            $options{'sort'} or push @echoLines,  join("  ", @statusHeaders); 
        } else {
            push @fileLines, $line; # pass all other label lines
            $options{'sort'} or push @echoLines, $line;
        }       
    }
    close $statusFileH;
    sortEchoLines(\@echoLines, \%echoLines);
    $options{'_suppress-echo_'} or print join("\n", @echoLines),"\n"; # echo selected values
    open $statusFileH, ">", $statusFile or die "could not open $statusFile for writing: $!\n"; # replace status file
    print $statusFileH join("\n", @fileLines),"\n";
    close $statusFileH;
}
sub getStatusLine { # parse an indidivual status line, protect undef as ''
    my($lines, $applyFilters, $delimiter, @in) = @_;
    my @out;
    foreach my $value(@in){
        defined $value or $value = '';
        push @out, $value;
    }    
    if($applyFilters){  # echo lines
        applyStatusFilters(\@out) or return;
        pop @out;  # remove user from echo lines, had been retained solely for sorting and filtering
        padEchoColumns(\@out); 
        @in = @out;
        @out = ();
        foreach my $i(@keepInEcho) { push @out, $in[$i] }
    }
    push @$lines, join($delimiter, @out);  
}
sub padEchoColumns {  # ensure pretty parsing of echoed status table
    my($line) = @_;
    my $deleted = $$line[$outputColumns{exit_status}] =~ m/deleted/;
    foreach my $column(keys %columnWidths){
        my $outWidth = $columnWidths{$column};    
        my $columnNumber = $outputColumns{$column};
        my $value = $$line[$columnNumber];
        defined $value or $value = "";
        $value =~ s/\s+$//;
        ($deleted and $column eq 'exit_status')  or $value = substr($value, 0, $outWidth - ($column eq 'job_name' ? 2 : 0));
        $column eq 'job_name' and $value .= " "; 
        $deleted or (length($value) or $value = $emptyChars{$column} x $outWidth);
        my $inWidth = length($value);
        $inWidth < $outWidth and $value .= ($padChars{$column} x ($outWidth - $inWidth));
        $$line[$columnNumber] = $value;
    }
}
#========================================================================

#========================================================================
# read job information out of the status file without updating it
# only suitable for tasks that don't depend on up-to-date job status
#------------------------------------------------------------------------
sub getJobStatusInfo { 
    %jobIDs = ();  # only collect static information that does not depend on status
    %successors = ();
    %exists = ();
    %allJobs = ();
    open my $statusFileH, "<", $statusFile or return;
    my $submittedTime;
    while(my $line = <$statusFileH>){
        chomp $line;
        my @line = split("\t", $line);
        $line[0] or next;    
        if ($line[$statusFields{jobID}] =~ m/^\d+$/) {# job lines and only job lines have jobID field all digits
            my $jobID = $line[$statusFields{jobID}];
            my $command = $line[$statusFields{command}];
            $jobIDs{$submittedTime}{$line[$statusFields{job}]} = $jobID;
            $successors{$jobID} = [$submittedTime, $line[$statusFields{successors}]];
            $exists{$command}++; 
            $allJobs{$jobID} = [$line[$statusFields{qType}], $line[$statusFields{array}], $line[$statusFields{targetScript}],
                                $line[$statusFields{command}], $line[$statusFields{instrsFile}], $line[$statusFields{scriptFile}],
                                $line[$statusFields{jobName}]];
        } elsif ($line[0] eq 'submitted') {# collect submission grouping for dependency tracking
            $submittedTime = $line[1];
        }       
    }
    close $statusFileH; 
}
#========================================================================

#========================================================================
# echo a pretty-parsed current version of a status file without updating it
#------------------------------------------------------------------------
sub echoStatusFile {
    my ($statusFile) = @_; 
    open my $statusFileH, "<", $statusFile or return;
    my (@echoLines, %echoLines);       
    while(my $line = <$statusFileH>){
        chomp $line;
        my @line = split("\t", $line);
        $line[0] or next;
        if ($line[$statusFields{jobID}] =~ m/^\d+$/) {# job lines and only job lines have jobID field all digits               
            my $echoArray = getEchoArray(\@echoLines, \%echoLines, \@line);
            getStatusLine($echoArray, 1, "  ",
                            $line[$statusFields{jobName}],
                            $line[$statusFields{array}] ? '@' : ' ',                                    
                            $line[$statusFields{jobID}], 
                            $line[$statusFields{exit_status}], 
                            $line[$statusFields{start_time}], 
                            $line[$statusFields{walltime}], 
                            $line[$statusFields{maxvmem}],
                            $line[$statusFields{job}], 
                            $line[$statusFields{predecessors}],                                 
                            $line[$statusFields{user}] ); 
        } elsif ($line[0] eq 'jobName') {# replace header line on echo
            $options{'sort'} or push @echoLines,  join("  ", @statusHeaders); 
        } else {
            $options{'sort'} or push @echoLines, $line;
        }       
    }
    close $statusFileH;
    sortEchoLines(\@echoLines, \%echoLines);
    print join("\n", @echoLines),"\n"; # echo selected values
}
#========================================================================

#========================================================================
# handle status filtering and sorting
#------------------------------------------------------------------------
sub checkSortColumn {
    $options{'sort'} or return;
    ($sortColumn, $sortOrder) = ($options{'sort'}, 'asc');
    $sortColumn =~ m|(\w+)\:(.+)| and ($sortColumn, $sortOrder) = ($1, "\L$2");
    defined $outputColumns{$sortColumn} or 
        die "unrecognized sort column: $sortColumn\nvalid columns are ".join(", ", @outputColumns)."\n";  
    ($sortOrder eq 'asc' or $sortOrder eq 'desc') or 
        die "unrecognized sort order: $sortOrder\nvalid sort orders are asc, desc\n";
    $sortIndex = $statusFields{$sortColumns{$sortColumn}};
}
sub getEchoArray {
    my ($echoArray, $echoHash, $line) = @_;
    $options{'sort'} or return $echoArray;
    my $value = $$line[$sortIndex];
    if($numericFilterSort{$sortColumn}){
        $value = numerizeFilterSortValue($sortColumn, $value);
        $value or $value = 0;
    }
    defined $value or $value = "";
    return \@{$$echoHash{$value}};
}
sub sortEchoLines {
    my ($echoArray, $echoHash) = @_;
    $options{'sort'} or return;
    my @values;
    if($sortOrder eq 'asc'){
        @values = $numericFilterSort{$sortColumn} ? sort {$a <=> $b} keys %$echoHash : sort {$a cmp $b} keys %$echoHash; 
    } else {
        @values = $numericFilterSort{$sortColumn} ? sort {$b <=> $a} keys %$echoHash : sort {$b cmp $a} keys %$echoHash; 
    }
    foreach my $value(@values){ push @$echoArray, @{$$echoHash{$value}} }
}
#------------------------------------------------------------------------
sub parseStatusFilters {
    $options{'filter'} or return;
    FILTER: foreach my $filter(split(",", $options{'filter'})){
        $filter or next;
        foreach my $filterOperator(@filterOperators){
            if($filter =~ m|(\w+)\s*$filterOperator\s*(.*)|){
                my ($column, $filterValue) = ($1, $2);
                my $columnNumber = $outputColumns{$column};
                defined $columnNumber or die "unrecognized column in filter $filter\nvalid columns are ".join(", ", @outputColumns)."\n";
                defined $filterValue or $filterValue = '';  
                if($filterOperator eq '>' or $filterOperator eq '<'){
                    $numericFilterSort{$column} or die "$column does not support numeric sorting\n";
                    my $tmpValue = $filterValue;
                    $filterValue = numerizeFilterSortValue($column, $filterValue);
                    defined $filterValue or die "unable to numerize filter value: $tmpValue\n".
                                                "for maxvmem, use:   1.234 or 1.234G\n".
                                                "for walltime use:   hh:mm:ss or hh:mm or seconds\n".
                                                "for start_time use: mm/dd/yy [hh:mm]\n";
                }                       
                push @statusFilters, [$column, $columnNumber, $filterOperator, $filterValue];
                next FILTER;
            }   
        }
        die "unrecognized operator in filter $filter\nvalid operators are ".join(", ", @filterOperators)."\n";
    }
}
sub applyStatusFilters {
    my($out) = @_;
    $options{'filter'} or return 1;
    foreach my $statusFilter(@statusFilters){
        my ($column, $columnNumber, $filterOperator, $filterValue) = @$statusFilter;
        my $value = $$out[$columnNumber]; 
        if($filterOperator eq '='){
            $value eq $filterValue or return; 
        } elsif($filterOperator eq '!='){
            $value eq $filterValue and return; 
        } elsif($filterOperator eq '~'){
            $value =~ m|$filterValue| or return; 
        } elsif($filterOperator eq '!~'){
            $value =~ m|$filterValue| and return;  
        } elsif($filterOperator eq '>'){
            $value = numerizeFilterSortValue($column, $value);
            defined $value or return;
            $value > $filterValue or return; 
        } elsif($filterOperator eq '<'){
            $value = numerizeFilterSortValue($column, $value);
            defined $value or return;
            $value < $filterValue or return; 
        }
    }
    return 1;
}
#------------------------------------------------------------------------
sub numerizeFilterSortValue {  # convert text entries into values suitable for numeric filtering and sorting
    my ($column, $value) = @_;
    defined $value or return;  # all numerization failures return undef
    if($column eq 'maxvmem'){  # maxvmem in GB
        $value = "\U$value";
        $value =~ m|(.+)G$| and $value = $1;
        ($value =~ m|^\d+\.\d+$| or $value =~ m|^\d+$|) or return;
    } elsif($column eq 'wall_time'){  # wall_time in seconds
        $value =~ m|^(.{1,2})\:(.{1,2})\:(.{1,2})$| and $value = $1*60*60 + $2*60 + $3;
        $value =~ m|^(.{1,2})\:(.{1,2})$| and $value = $1*60*60 + $2*60;
        $value =~ m|^\d+$| or return;    
    } elsif($column eq 'start_time'){  # start_time in minutes
        $value =~ m/^(Sun|Mon|Tue|Wed|Thu|Fri|Sat) (.+)/ and $value = $2;
        my ($date, $time) = split(" ", $value);
        my ($nDays, $nMin) = (0, 0);
        $date or return;
        $date =~ m|^(.{1,2})/(.{1,2})/(.{1,2})$| or return;
        $nDays = ($3-1)*365 + ($1-1)*30 + ($2-1);
        if($time){
            $time =~ m|(.{1,2})\:(.{1,2})| or return;
            $nMin = $1*60 + $2;
        }
        $value = $nDays*24*60 + $nMin;
        $value =~ m|^\d+$| or return;    
    }  elsif($column eq 'job_ID'){  # job_ID expected to be numeric already
        $value =~ m|^\d+$| or return;    
    }  
    return $value;  
}
#========================================================================

#========================================================================
# collect job state and status information
#------------------------------------------------------------------------
sub getJobStates { #retrieve job states for jobs in queue or running
    my ($jobStates) = @_; 
    my $qstat; #list of all queued jobs
    if($qType eq 'SGE'){
        $qstat = qx|$schedulerDir/qstat -u '*'|; 
    } elsif($qType eq 'PBS') {
        $qstat = qx|$schedulerDir/qstat|;
    } elsif($qType eq 'slurm') {
        $qstat = qx|$schedulerDir/squeue|;
    }
    $qstat or return;    
    my @qstat = split("\n", $qstat);
    $qstat[2] or return; 
    my @jobs = @qstat[2..$#qstat];
    my $stateI = $qType eq 'slurm' ? 5 : 4;
    for my $job(@jobs){ #qstat/squeue formats are similar enough to use same parsing
        $job =~ m/^\s*(.*)$/; #strip leading white space
        $job = $1;
        my @fields = split(/\s+/, $job);
        $fields[0] =~ m/^(\d+)/; 
        my $jobID = $1;        
        my $state = $fields[$stateI];
        $$jobStates{$jobID} = $state;
    }   
}  
sub getJobStatus{ # expects that getJobStates has already been called
    my ($jobName, $jobID, $jobStates, $jobInfo, $justDeleted, $array, $qType) = @_;
    $jobID or return;    
    if($justDeleted and $$justDeleted{$jobID}){ # force job status for newly deleted jobs
       $$jobInfo{exit_status} = $$justDeleted{$jobID} eq 'Eqw' ? 'deleted after error' : 'deleted';
       return;
    }
    if($$jobStates{$jobID}){ # jobs still in queue (or recently completed on PBS)
        if($qType eq 'SGE'){ # SGE loses qstat information as soon as job completes; if in queue, get most info from qstat
            getSgeJobInfo($jobID, $jobInfo);
            getLogFileInfo($jobName, $jobID, $jobInfo, $array, $qType, 1);  # get just the start time from the log file
            $$jobInfo{start_time} or $$jobInfo{start_time} = '';
            $$jobInfo{exit_status} = $$jobStates{$jobID}; # place queue status into exit_status while job is in queue            
            $$jobInfo{walltime} = '';  # walltime not available in SGE qstat   
        } elsif($qType eq 'slurm'){
            getSlurmJobInfo($jobID, $jobInfo);
            getLogFileInfo($jobName, $jobID, $jobInfo, $array, $qType, 1);  # get just the start time from the log file
            $$jobInfo{start_time} or $$jobInfo{start_time} = '';
            $$jobInfo{exit_status} = $$jobStates{$jobID}; # place queue status into exit_status while job is in queue             
        } else { # PBS maintains qstat return for some variable time; job state tells whether job is truly completed
            if($$jobStates{$jobID} eq 'C'){ # completed jobs; get info from log file
                getLogFileInfo($jobName, $jobID, $jobInfo, $array, $qType);
            } else { # queued or running jobs; get info from qstat
                getPbsJobInfo($jobID, $jobInfo, $array); 
                getLogFileInfo($jobName, $jobID, $jobInfo, $array, $qType, 1);  # get just the start time from the log file
                $$jobInfo{start_time} or $$jobInfo{start_time} = '';
                $$jobInfo{exit_status} = $$jobStates{$jobID}; # place queue status into exit_status while job is in queue
            }          
        }
    } else { # completed jobs; get info from log file
        getLogFileInfo($jobName, $jobID, $jobInfo, $array, $qType);
    }
}
sub getLogFileInfo { # job is completed but log file information not yet captured into status file
    my ($jobName, $jobID, $jobInfo, $array, $qType, $startTimeOnly) = @_;
    my $logFiles = getLogFiles($qType, $jobName, $jobID, $array);
    if($array){ # for array jobs, collect min starttime, max walltime and maxvmem values over all jobs
        my ($minStart, $maxSecs, $maxVmem) = (1E9, 0, 0);
        foreach my $taskFile(@$logFiles){
            -e $taskFile or next;
            parseLogFile(\my%taskInfo, $taskFile, undef, $startTimeOnly);
            unless($minStart < $taskInfo{start_time_}){
                $minStart = $taskInfo{start_time_};
                $$jobInfo{start_time} = $taskInfo{start_time};
            } 
            $startTimeOnly and next;
            $$jobInfo{exit_status} = $$jobInfo{exit_status} ? $$jobInfo{exit_status} : $taskInfo{exit_status}; # if any job is in error, preserve that status 
            unless($maxSecs > $taskInfo{seconds}){
                $maxSecs = $taskInfo{seconds};
                $$jobInfo{walltime} = $taskInfo{walltime};
            } 
            unless($maxVmem > $taskInfo{maxvmem_}){
                $maxVmem = $taskInfo{maxvmem_};
                $$jobInfo{maxvmem} = $taskInfo{maxvmem};
            } 
        }
        $$jobInfo{start_time} or $$jobInfo{start_time} = '';
    } else { 
        my ($logFile) = @$logFiles;
        unless(-e $logFile){
            $startTimeOnly and $$jobInfo{start_time} = '';
            return;
        }
        parseLogFile($jobInfo, $logFile, undef, $startTimeOnly);
    }
}
sub parseLogFile { # extract and format the job information as reported by the wrapper to the user script
    my ($jobInfo, $logFile, $isContents, $startTimeOnly) = @_;
    # read the yaml-formatted job metadata as printed by jobManager utilities
    my $yamls = loadYamlFromString( $isContents ? $logFile : slurpFile($logFile) );
    my %jmData;
    foreach my $yaml(@{$$yamls{parsed}}){
        my $jm = $$yaml{'job-manager'} or next;
        foreach my $key(keys %$jm){
            $jmData{$key} = $$jm{$key}[0]
        }
    }
    $$jobInfo{start_time} = $jmData{started};
    $$jobInfo{start_time} or $$jobInfo{start_time} = "";
    $$jobInfo{start_time_} = $$jobInfo{start_time} ? numerizeFilterSortValue('start_time', $$jobInfo{start_time}) : 1E9;
    $startTimeOnly and return;  
    # if job started, but end info is not present in log file, then job timed out
    # if neither start nor end info is present in log file, assume system write of log file is still pending (transient state)
    my %nullValues=(exit_status=>$$jobInfo{start_time} ? 137        : "pending", # 137 = SGE timed out exit status
                    walltime=>   $$jobInfo{start_time} ? "99:99:99" : "",        # use "infinity" times to signal timing out, or "unknown"
                    seconds=>    $$jobInfo{start_time} ? 9999999    : 0, 
                    maxvmem=>    "0K");                                          # can't determine memory of timed out job
    foreach my $key(qw(exit_status walltime seconds maxvmem)){
        $$jobInfo{$key} = $jmData{$key};
        defined $$jobInfo{$key} or $$jobInfo{$key} = $nullValues{$key};
    }
    chop $$jobInfo{maxvmem}; # change memory readout to G instead of K as supplied by time
    $$jobInfo{maxvmem} /= $memoryCorrection; # apply /usr/bin/time bug memory correction, if needed (see 'q' main script for details)
    $$jobInfo{maxvmem_} = $$jobInfo{maxvmem};
    $$jobInfo{maxvmem} = int($$jobInfo{maxvmem}/1E3+0.5)/1E3."G";
    $$jobInfo{walltime} =~ m/(.+)\.\d+/ and $$jobInfo{walltime} = $1;
    length($$jobInfo{walltime}) == 4 and $$jobInfo{walltime} = "00:0".$$jobInfo{walltime};
    length($$jobInfo{walltime}) == 5 and $$jobInfo{walltime} = "00:".$$jobInfo{walltime};
    length($$jobInfo{walltime}) == 7 and $$jobInfo{walltime} = "0".$$jobInfo{walltime}; 
}
#========================================================================

#========================================================================
# interface with SGE for queued or running jobs
#------------------------------------------------------------------------
sub getSgeJobInfo { # retrieve detailed information on a queued or running SGE job
    my ($jobID, $jobInfo) = @_;
    my $qstat = qx|$schedulerDir/qstat -j $jobID|;
    $qstat or return;
    foreach my $key(qw(jid_predecessor_list jid_successor_list)){ # is this used anywhere anymore??
        $qstat =~ m/$key.*?\:\s*(.*)\n/ and $$jobInfo{$key} = $1;
    }
    foreach my $key(qw(maxvmem)){
        $qstat =~ m/$key=(.*?)(,|\s)/ and $$jobInfo{$key} = $1;
    }    
    my %exp = (K=>3,M=>6,G=>9); # change memory readout to G for status display 
    if($$jobInfo{maxvmem} and $$jobInfo{maxvmem} =~ m/^(\d+\.*\d*)((K|M|G))$/){   
        $$jobInfo{maxvmem} = $1 * (10**$exp{$2});   
        $$jobInfo{maxvmem} = int($$jobInfo{maxvmem}/1E6+0.5)/1E3."G"; 
    }          
}
#========================================================================

#========================================================================
# interface with Slurm for queued or running jobs
#------------------------------------------------------------------------
sub getSlurmJobInfo { # retrieve detailed information on a queued or running Slurm job
    my ($jobID, $jobInfo) = @_;
    my $seff = qx|seff $jobID|;
    $seff or return;
    $$jobInfo{walltime} = $seff =~ m/Job Wall-clock time\: (\S+)/  ? $1 : "";
    $$jobInfo{maxvmem}  = $seff =~ m/Memory Utilized\: (\S+)/  ? $1 : "";
    #Job Wall-clock time: 00:00:35
    #Memory Utilized: 0.00 MB (estimated maximum)
    my %exp = (KB=>3,MB=>6,GB=>9); # change memory readout to G for status display 
    if($$jobInfo{maxvmem} and $$jobInfo{maxvmem} =~ m/^(\d+\.*\d*) ((KB|MB|GB))$/){   
        $$jobInfo{maxvmem} = $1 * (10**$exp{$2});   
        $$jobInfo{maxvmem} = int($$jobInfo{maxvmem}/1E6+0.5)/1E3."G"; 
    } 
}
#========================================================================

#========================================================================
# interface with PBS for queued or running jobs
#------------------------------------------------------------------------
sub getPbsJobInfo { # retrieve detailed information on a PBS job
    my ($jobID, $jobInfo, $array) = @_;
    my $qstat = $array ? "qstat -f -t $jobID\[]" : "qstat -f $jobID" ; 
    $qstat = qx/$qstat 2> \/dev\/null/;
    $qstat or return; 
    if($array){
        getPbsArrayJobInfo($jobID, $qstat, $jobInfo);
    } else {
        getPbsJobInfo_($qstat, $jobInfo);
    }   
    my %exp = (KB=>3,MB=>6,GB=>9); # change memory readout to G for status display 
    if($$jobInfo{maxvmem} and "\U$$jobInfo{maxvmem}" =~ m/^(\d+\.*\d*)((KB|MB|GB))$/){   
        $$jobInfo{maxvmem} = $1 * (10**$exp{$2});   
        $$jobInfo{maxvmem} = int($$jobInfo{maxvmem}/1E6+0.5)/1E3."G"; 
    }            
    if($$jobInfo{walltime}){
        $$jobInfo{start_time} = '';
    } else {
        $$jobInfo{walltime} = '';
        $$jobInfo{start_time} or $$jobInfo{start_time} = '';
    }
}
sub getPbsArrayJobInfo { # for array jobs, collect max walltime and maxvmem values over all jobs
    my ($jobID, $qstat, $jobInfo) = @_;
    my @qstats = split(/Job Id: $jobID\[\d+\]/, $qstat);
    shift @qstats;
    my ($maxSecs, $maxMaxVMem) = (0, 0);
    my %exp = (KB=>3,MB=>6,GB=>9);    
    foreach my $qstat(@qstats){    
        getPbsJobInfo_($qstat, \my%taskInfo);    
        $$jobInfo{exit_status} = $$jobInfo{exit_status} ? $$jobInfo{exit_status} : $taskInfo{exit_status}; # if any job is in error, preserve that status 
        my $arraySecs = getPbsJobSecs($taskInfo{walltime});
        unless($maxSecs > $arraySecs){
            $maxSecs = $arraySecs;
            $$jobInfo{walltime} = $taskInfo{walltime};
        }                  
        if($taskInfo{maxvmem} and "\U$taskInfo{maxvmem}" =~ m/^(\d+\.*\d*)((KB|MB|GB))$/){                         
            my $arrayMaxVMem = $1 * (10**$exp{$2});    
            unless($maxMaxVMem >= $arrayMaxVMem){ # preserve max maxvmem
                $maxMaxVMem = $arrayMaxVMem;
                $$jobInfo{maxvmem} = $taskInfo{maxvmem}
            }                
        }                  
    } 
}
sub getPbsJobInfo_ { # process an invidual job's PBS qstat
    my ($qstat, $jobInfo) = @_;
    foreach my $key(qw(job_state start_time exit_status resources_used.walltime resources_used.vmem)){
        $qstat =~ m/$key\s+=\s+(.*)\n/ and $$jobInfo{$key} = $1;
        $$jobInfo{$key} and $$jobInfo{$key} =~ s/\s+$//;
    }
    defined $$jobInfo{exit_status} or $$jobInfo{exit_status} = $$jobInfo{job_state}; # place queue status into exit_status while job is in queue
    $$jobInfo{walltime} = $$jobInfo{'resources_used.walltime'}; # convert from PBS to SGE value names for internal use
    $$jobInfo{maxvmem} = $$jobInfo{'resources_used.vmem'};
}
sub getPbsJobSecs { # convert wall clock duration format to seconds to allow determination of max job duration
    my ($time) = @_;
    $time or return 0;
    my @multipliers = (1,60,60*60,60*60*24);
    my @time = reverse(split("\:", $time));
    my $secs = 0;
    foreach my $i(0..3){
        defined $time[$i] or last;
        $secs += $time[$i] * $multipliers[$i];
    }
    return $secs;
}
#========================================================================

1;

