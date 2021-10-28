use strict;
use warnings;

# create templates for the data-specific config file
# modified by end user to simplify calls to the pipeline

# working variables
use vars qw($config $mainDir $launcherDir $pipeline
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
pipeline: $pipelineName

variables:

shared:
\n" : 

"---
#--------------------------------------------------------------
# copy/modify this file as needed to identify specific $pipelineName
# data/sample(s) to be analyzed and to override default option values
#--------------------------------------------------------------
pipeline: $pipelineName

#--------------------------------------------------------------
# you may define and use variables to help avoid repetition and typing errors 
# by convention, variable names are ALL_UPPER_CASE
#--------------------------------------------------------------
# variables:
#     DATA_DIR: \$HOME/data # can cascade from pre-existing environment variables
# command:
#     optionFamily:
#         files: [\$DATA_DIR/file1.txt, \${DATA_DIR}/file2.txt] # either bash-like format works
#--------------------------------------------------------------
variables:

#--------------------------------------------------------------
# options defined here apply to all relevant commmands
#--------------------------------------------------------------
shared:

#--------------------------------------------------------------
# options defined here apply to the individual named commmands
#--------------------------------------------------------------\n";
}

my $executeComments =
"#--------------------------------------------------------------
# the ordered list of commands to execute (comment out commands you do not wish to run)
#--------------------------------------------------------------\n";

#---------------------------------------------------------
# write a config template to STDOUT
#---------------------------------------------------------
sub writeDataFileTemplate {
    ($allOptions, $addComments) = @_;
    
    # get the list of pipeline-specific commands (universal commands are for monitoring, not running)
    my $cmds = $$config{commands};
    my @commands = sort { $$cmds{$a}{order}[0] <=> $$cmds{$b}{order}[0] }
                   map { $$cmds{$_}{universal}[0] ? () : $_ }
                   keys %$cmds;
                   
    # pull the option families, keeping track of how many commands invoked each family
    # this list does not include universal option families
    my %optFams;
    foreach my $command(@commands){
        !$$cmds{$command}{optionFamilies} and next;
        map { push @{$optFams{$_}}, $command } @{$$cmds{$command}{optionFamilies}};
    }

    # print the file leader
    print getLeader($$config{pipeline}{name}[0], $addComments);                     

    # print the options families invoked by only one command, in command order
    foreach my $command(@commands){
        my $desc = getTemplateValue($$cmds{$command}{description});
        $addComments and print "# $desc\n"; 
        print "$command:\n";
        my $cmd = $$cmds{$command};
        my @pipelineOptionFamilies = $$cmd{optionFamilies} ? @{$$cmd{optionFamilies}}: ();
        foreach my $family(@pipelineOptionFamilies, @universalTemplateFamilies){
            writeOptionFamily($command, $family);
        }
        print "\n";
    }
    
    # print the command execution sequence
    print $addComments ? $executeComments : "";
    print "execute:\n";
    foreach my $command(@commands){
        print "$indent- $command\n"
    }
    print "\n";
}

#---------------------------------------------------------
# write one family set of options
#---------------------------------------------------------
sub writeOptionFamily {
    my ($command, $family) = @_;
    
    # get any developer recommendations beyond universal options
    my $cmd = $$config{commands}{$command};
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
        $isRequired and $value eq 'null' and $value = $requiredLabel;        
        !$allOptions and $value ne $requiredLabel and next;          
        #my $desc = getTemplateValue($$opt{description});
        #my $type = getTemplateValue($$opt{type});
        #$addComments and print "$indent$indent# $desc ($type)\n";
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

