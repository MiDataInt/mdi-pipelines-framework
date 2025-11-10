use strict;
use warnings;

# create templates for the data-specific config file
# modified by end user to simplify calls to the pipeline

# working variables
use vars qw($config $launcherDir $pipeline $pipelineSuite
            @universalTemplateFamilies);
my ($allOptions, $addComments);
my $indent = " " x 4;
our $requiredLabel = '_REQUIRED_';

#---------------------------------------------------------
# helpful comments for the file (can be supressed)
#---------------------------------------------------------
sub getLeader {
    my ($pipelineName, $addComments) = @_;
    !$addComments ?
"---
pipeline: $pipelineSuite/$pipelineName:latest

variables:

shared:
\n" : 

"---
#--------------------------------------------------------------
# identify the pipeline in format \[pipelineSuite/\]pipelineName\[:suiteVersion\]
# suiteVersion is v#.#.#, a tag or branch, pre-release or latest (the default)
#--------------------------------------------------------------
pipeline: $pipelineSuite/$pipelineName:latest

#--------------------------------------------------------------
# you can use variables to avoid repetition and typing errors 
# by convention, variable names are ALL_UPPER_CASE
#--------------------------------------------------------------
# variables:
#     DATA_DIR: \${HOME}/data # can cascade from other environment variables
# action:
#     optionFamily:
#         files: [\$DATA_DIR/file1.txt, \${DATA_DIR}/file2.txt] # either format works, \${} recommended
#--------------------------------------------------------------
variables:

#--------------------------------------------------------------
# options defined here apply to all relevant actions
#--------------------------------------------------------------
shared:

#--------------------------------------------------------------
# options defined here apply to the individual named actions
#--------------------------------------------------------------\n";
}

my $executeComments =
"#--------------------------------------------------------------
# ordered list of actions to execute (comment out actions you do not wish to run)
#--------------------------------------------------------------\n";

#---------------------------------------------------------
# write a config template to STDOUT
#---------------------------------------------------------
sub writeDataFileTemplate {
    ($allOptions, $addComments) = @_;
    
    # get the list of pipeline-specific actions (universal commands are for monitoring, not running)
    my $cmds = $$config{actions};
    my @actions = sort { $$cmds{$a}{order}[0] <=> $$cmds{$b}{order}[0] }
                   map { $$cmds{$_}{universal}[0] ? () : $_ }
                   keys %$cmds;
                   
    # pull the option families, keeping track of how many actions invoked each family
    # this list does not include universal option families
    my %optFams;
    foreach my $action(@actions){
        !$$cmds{$action}{optionFamilies} and next;
        map { push @{$optFams{$_}}, $action } @{$$cmds{$action}{optionFamilies}};
    }

    # print the file leader
    print getLeader($$config{pipeline}{name}[0], $addComments);                     

    # print the options families invoked by only one action, in action order
    foreach my $action(@actions){
        my $desc = getTemplateValue($$cmds{$action}{description});
        $addComments and print "# $desc\n"; 
        print "$action:\n";
        my $cmd = $$cmds{$action};
        my @pipelineOptionFamilies = $$cmd{optionFamilies} ? @{$$cmd{optionFamilies}}: ();
        foreach my $family(@pipelineOptionFamilies, @universalTemplateFamilies){
            writeOptionFamily($action, $family);
        }
        print "\n";
    }
    
    # print the action execution sequence
    print $addComments ? $executeComments : "";
    print "execute:\n";
    foreach my $action(@actions){
        print "$indent- $action\n"
    }
    print "\n";
}

#---------------------------------------------------------
# write one family set of options
#---------------------------------------------------------
sub writeOptionFamily {
    my ($action, $family) = @_;
    
    # get any developer recommendations beyond universal options
    my $cmd = $$config{actions}{$action};
    my %recs;
    if ($cmd and $$cmd{$family} and $$cmd{$family}{recommended}) {
        my $recs = $$cmd{$family}{recommended};
        foreach my $option(keys %$recs){
            $recs{$option} = $$recs{$option}[0];
        }
    }  
    
    # generate the output
    my $indent = " " x 4;
    my $options = $$config{optionFamilies}{$family}{options};
    my @options = sort { $$options{$a}{order}[0] <=> $$options{$b}{order}[0] } keys %$options;
    @options or return;
    print "$indent$family:\n";     
    my $valueIndent = 4 + 4 + 16;
    foreach my $option(@options){
        my $opt = $$options{$option};
        my $isRequired = $$opt{required}[0];
        my $value      = defined $recs{$option} ? $recs{$option} : $$opt{default}[0];
        !$isRequired and !defined $value and $value = 'null';        
        $isRequired and (!defined $value or $value eq 'null') and $value = $requiredLabel;  
        !$allOptions and $value ne $requiredLabel and next;          
        $$opt{type}[0] eq 'string' and $value =~ m/,/ and $value = "\"$value\"";
        my $left = "$indent$indent$option:";
        my $spaces = $valueIndent - length($left);
        $spaces < 1 and $spaces = 1;
        $spaces = " " x $spaces;
        print "$left$spaces$value\n";
    }    
}
sub getTemplateValue {
    my ($array) = @_;
    my $value = $$array[0];
    $value =~ s/^\"//;
    $value =~ s/\"$//;
    $value =~ s/^'//;
    $value =~ s/'$//;
    $value;
}

1;
