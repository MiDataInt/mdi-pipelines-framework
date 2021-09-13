use strict;
use warnings;

# working variables
use vars qw($jobManagerName %commands %commandOptions %optionInfo);
my $commandTabLength = 12; 
my $optionTabLength = 20;
our $separatorLength = 87;
our $leftPad = (" ") x 4;
our $errorHighlight = "!" x 60;
our @optionGroups = qw(main submit status job rollback);  # ensure that similar options group together
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
    print $message ? "\n$message\n\n" : "\n";
    my $jmName = "$leftPad$jobManagerName";
    print 
        "usage\n".
        "$jmName <pipeline> [options] # alias for './<pipeline>/<pipeline> [options]'\n".
        "$jmName <command> [options] <data.yml ...> [options] # apply command to data.yml(s)\n".
        "$jmName <command> --help\n".
        "$jmName --help\n\n";        
    if($command){
        $commands{$command} ? reportOptionHelp($command) : reportCommandsHelp();
    } else {
        reportCommandsHelp();
    }
    my $exitStatus = $die ? 1 : 0;
    exit $exitStatus; 
}
sub reportCommandsHelp { # help on the set of available commands, organized by topic
    print "\navailable commands\n\n";
    reportCommandChunk("job submission",              qw(submit extend));  
    reportCommandChunk("status and result reporting", qw(status report script));   
    reportCommandChunk("error handling",              qw(delete));           
    reportCommandChunk("pipeline management",         qw(rollback purge));       
}
sub reportOptionHelp { 
    my ($command) = @_;
    print "\n";
    print "$jobManagerName $command: ${$commands{$command}}[1]\n";
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
    return $command, " " x ($commandTabLength - length($command)), ${$commands{$command}}[1], "\n";
}
#========================================================================

1;
