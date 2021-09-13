use strict;
use warnings;

# functions that provide executable help feedback on the command line

# working variables
use vars qw($config %optionValues $helpCommand $helpCmd);
my $commandTabLength = 15;
my $optionTabLength = 20;
our $leftPad = (" ") x 4;
our $errorSeparator = "!" x 60;

#------------------------------------------------------------------------------
# show a listing of the commands available for a pipeline
#------------------------------------------------------------------------------
sub showCommandsHelp {
    my ($error, $exit) = @_;
    $error and print "\n".$errorSeparator."\n$error\n".$errorSeparator."\n";    
    my $pName = "$leftPad$$config{pipeline}{name}[0]";
    my $desc = getTemplateValue($$config{pipeline}{description});
    my $usage =
        "$$config{pipeline}{name}[0]: $desc\n\n".
        "usage\n".
        "$pName <data.yml> [options]           # run all commands found in data.yml\n".
        "$pName <command> <data.yml> [options] # run one command, with options from data.yml\n".
        "$pName <command> <options>            # run one command, all options from command line\n".
        "$pName <command> --help\n".
        "$pName --help\n";
    print "\n$usage\n";
    my $commands = $$config{commands};
    my $prevLevel = -1;
    foreach my $name(sort {
        ($$commands{$a}{universal}[0] || 0) <=> ($$commands{$b}{universal}[0] || 0) or
        $$commands{$a}{order}[0] <=> $$commands{$b}{order}[0]
    } keys %$commands){
        my $level = $$commands{$name}{universal}[0] || 0;
        if($level != $prevLevel){
            print $level ? "\ngeneral workflow commands\n" : "pipeline specific commands\n";
            $prevLevel = $level;
        }
        my $command = $$commands{$name};
        $$command{hidden}[0] and next;
        my $commandLength = length($name);
        my $spaces = (" ") x ($commandTabLength - $commandLength);
        my $desc = getTemplateValue($$command{description});
        print  "$leftPad"."$name$spaces$desc\n";
    }
    print  "\n"; 
    $exit and exit 1;
}

#------------------------------------------------------------------------------
# show a listing of the options available for a pipeline command
# the list can show either descriptions or the values currently in use
#------------------------------------------------------------------------------
sub showOptionsHelp {
    my ($error, $useValues, $suppressExit) = @_;
    $error and print "\n".$errorSeparator."\n$error\n".$errorSeparator."\n";
    my $pName = $$config{pipeline}{name}[0];
    my $pDesc = getTemplateValue($$config{pipeline}{description});
    print "\n$pName: $pDesc\n";
    if ($helpCommand) {
        my $cDesc = $$config{commands}{$helpCommand}{description}[0];
        $cDesc =~ s/^"//;
        $cDesc =~ s/"$//;
        print "$helpCommand: $cDesc\n\n";
    } 
    my %familySeen;
    foreach my $family(sort { getFamilyOrder($a) <=> getFamilyOrder($b) } getAllOptionFamilies($helpCmd)){
        $familySeen{$family} and next;
        $familySeen{$family}++;
        my $options = getFamilyOptions($family);
        scalar(keys %$options) or next;
        print "$family options\n";        
        foreach my $longOption(sort { getOptionOrder($a, $options) <=> getOptionOrder($b, $options) }
                                     keys %$options){
            my $option = $$options{$longOption};
            $$option{hidden}[0] and next;
            my $shortOption = $$option{short}[0];
            $shortOption = $shortOption eq 'null' ? "" : "-$$option{short}[0],";
            my $left = "$shortOption--$longOption";
            my $leftLength = length($left);
            my $nSpaces = $optionTabLength - $leftLength;
            my $spaces = (" ") x ($nSpaces > 0 ? $nSpaces : 0);
            if($useValues){
                my $value = $optionValues{$longOption};
                if($$option{type}[0] eq "boolean"){
                    $value = $value ? 'true' : 'false';
                } elsif(!defined $value){
                    $value = "null";
                }
                print "$leftPad"."$left$spaces$value\n";            
            } else {
                my $type = $$option{type}[0] ? "<$$option{type}[0]> " : "";
                my $required = $$option{required}[0] ? "*REQUIRED*" : ($$option{default}[0] ? "[$$option{default}[0]]" : "");                
                my $desc = getTemplateValue($$option{description});
                my $right = "$type$desc $required";
                print  "$leftPad"."$left$spaces$right\n";                
            }
        }
        $useValues or print "\n";
    }
    $suppressExit or exit 1;
}
sub getFamilyOrder {
    my ($family) = @_;
    my $x = $$config{optionFamilies}{$family};
    $x or return 0;     
    ($$x{order}[0] || 0) + ($$x{universal}[0] ? 1000 : 0);
}
sub getOptionOrder {
    my ($optionName, $options) = @_;
    my $option = $$options{$optionName};     
    $option or return 0;
    $$option{order}[0] || 0;
}

#------------------------------------------------------------------------------
# throw an error message and exit (but don't die to avoid compile error from require of launcher)
#------------------------------------------------------------------------------
sub throwError {
    print "\n$errorSeparator\n$_[0]\n$errorSeparator\n\n";
    exit 1;
}
sub throwConfigError { # thrown when a configuration file is malformed
    my ($message, @keys) = @_;
    $message or $message = "";
    my $key = join(" : ", @keys);
    my $pattern =
"\nexpected/allowed patterns are:

pipeline: name
variables:
    VAR_NAME: value
shared:
    optionFamily:
        option: value
command:
    optionFamily:
        option: value
execute:
    - command";
    showOptionsHelp("malformed config file near '$key'\n".$message.$pattern);
}

#sub showDependencyHelp {
#    my ($suppressExit) = @_;
#    foreach my $dependency(@dependencies){
#        my $commandLength = length($$dependency{name});
#        my $spaces = (" ") x ($commandTabLength - $commandLength);        
#        my $path = qx(bash -c "command -v $$dependency{name}");
#        print "$$dependency{name}$spaces".($path ? $path : "!!! MISSING !!!\n");
#    }
#    $suppressExit or exit;
#}

1;

