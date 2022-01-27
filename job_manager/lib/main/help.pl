use strict;
use warnings;

# working variables
use vars qw($jobManagerName %commands %commandOptions %optionInfo);
my $jmName = $ENV{JOB_MANAGER_NAME} ? $ENV{JOB_MANAGER_NAME} : $jobManagerName;
my $commandTabLength = 12; 
my $optionTabLength = 20;
our $separatorLength = 87;
our $leftPad = (" ") x 2;
our $errorHighlight = "!" x 80;
our @optionGroups = qw(main submit status job rollback install server);  # ensure that similar options group together
my %useOptionGroupDelimiter = (submit=>1, extend=>1, resubmit=>1);  # break long options lists into separate groups

#========================================================================
# provide help feedback on command line
#------------------------------------------------------------------------
sub throwError {
    my ($message, $command) = @_;
    reportUsage("$errorHighlight\n$message\n$errorHighlight", $command, 1);
}
sub reportUsage { # program help, always exits 
    my ($message, $command, $die) = @_;
    print "\n>>> Michigan Data Interface (MDI) <<<\n";
    print $message ? "\n$message\n\n" : "\n";
    my $jmName = "$leftPad$jmName";
    print 
        "usage:\n".
        "$jmName <pipeline> <data.yml> [options]  # run all pipeline actions in data.yml\n".
        "$jmName <pipeline> <action> <data.yml> [options] # run one action from data.yml\n".
        "$jmName <pipeline> <action> <options>    # run one action, all options from command line\n".
        "$jmName <command> [options] <data.yml ...> [options] # apply manager command to data.yml(s)\n".
        "$jmName <command> [options]              # additional manager command shortcuts\n".
        "$jmName <pipeline> <action> --help       # pipeline action help\n".
        "$jmName <pipeline> --help                # summarize pipeline actions\n". 
        "$jmName <command> --help                 # manager command help\n".
        "$jmName --help                           # summarize manager commands\n";           
    if($command){
        $commands{$command} ? reportOptionHelp($command) : reportCommandsHelp();
    } else {
        reportCommandsHelp();
    }
    my $exitStatus = $die ? 1 : 0;
    exit $exitStatus; 
}
sub reportCommandsHelp { # help on the set of available commands, organized by topic
    print "\navailable commands:\n\n";
    reportCommandChunk("job submission",              qw(submit extend));  
    reportCommandChunk("status and result reporting", qw(status report script));   
    reportCommandChunk("error handling",              qw(delete));           
    reportCommandChunk("pipeline management",         qw(rollback purge));  
    reportCommandChunk("server management",           qw(initialize install add list build server));  
}
sub reportOptionHelp { 
    my ($command) = @_;
    print "\n";
    print "$jmName $command: ${$commands{$command}}[1]\n";
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
            my $nSpaces = $optionTabLength - length($option);
            $nSpaces < 1 and $nSpaces = 1;
            $parsedOptions{$optionGroup}{$groupOrder} = "$leftPad$option".(" " x ($nSpaces))."$optionHelp\n";
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
        print $leftPad."none\n";
    }
    print "\n";
}
sub reportCommandChunk {
    my ($header, @commands) = @_;
    print $leftPad."$header:\n";
    foreach my $command (@commands){
        print $leftPad, $leftPad, getCommandLine($command);
    }
    print "\n";
}
sub getCommandLine {
    my ($command) = @_;
    return $command, " " x ($commandTabLength - length($command)), ${$commands{$command}}[1], "\n";
}
#========================================================================

1;
