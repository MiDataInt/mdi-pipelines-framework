use strict;
use warnings;

# subs for handle configuration .yml files

# working variables
use vars qw($launcherDir $pipelineDir $optionsDir
            $configFile $config
            %optionArrays %nTasks %conda);

#------------------------------------------------------------------------------
# load a composite, i.e. assembled version of a pipeline's configuration
#------------------------------------------------------------------------------
sub loadPipelineConfig {
    
    # load the pipeline-specific and universal configs
    my $launcher = loadYamlFile("$launcherDir/commands.yml", 0, 1);
    my $pipeline = loadYamlFile("$pipelineDir/pipeline.yml", 2, 1, 1); # highest priority, allows modules
    my @optionFamilies = (loadYamlFile("$launcherDir/options.yml", 1, 1));
    my %loaded = (universal => 1);

    # cascade to add option families invoked by a pipeline action
    foreach my $action(keys %{$$pipeline{actions}}){ 
        my $optionFamilies = $$pipeline{actions}{$action}{optionFamilies} or next;
        ref($optionFamilies) eq 'ARRAY' or next;
        foreach my $optionFamily(@$optionFamilies){
            $loaded{$optionFamily} and next;
            $loaded{$optionFamily} = 1;
            my $ymlFile = "$optionsDir/$optionFamily.yml";
            -e $ymlFile and push @optionFamilies, loadYamlFile("$ymlFile", 1, 1);
        }
    }
    
    # merge information into a single, final config file hash
    mergeYAML($launcher, $pipeline, @optionFamilies);  
}

#------------------------------------------------------------------------------
# print configuration to log stream, i.e. all option values/dependencies for all tasks
#     this output is read by job manager to make scheduler queuing decisions
# expand options get the set of option values for each required task
#------------------------------------------------------------------------------
sub reportAssembledConfig {
    my ($action, $condaPaths) = @_;
    my $cmd = getCmdHash($action);
    my $indent = "    ";
    
    # print the config header, top-level metadata
    my $pName = $$config{pipeline}{name}[0];
    my $desc = getTemplateValue($$config{pipeline}{description});
    my $thread = $$cmd{thread}[0] || "default";
    my $report = "";
    $report .= "---\n";
    $report .= "pipeline:\n";
    $report .= $indent."name: $pName\n";
    $report .= $indent."description: \"$desc\"\n";
    $report .= "execute: $action\n";
    $report .= "thread: $thread\n";
    $report .= "nTasks: $nTasks{$action}\n";
    $report .= "$action:\n";
    
    # print the options
    my %familySeen;
    my @taskOptions;
    foreach my $family(sort { getFamilyOrder($a) <=> getFamilyOrder($b) } getAllOptionFamilies($cmd)){
        $familySeen{$family} and next;
        $familySeen{$family}++;
        my $options = getFamilyOptions($family);        
        %$options and $report .= "$indent$family:\n";
        foreach my $longOption(sort { getOptionOrder($a, $options) <=> getOptionOrder($b, $options) }
                                     keys %$options){
            my $option = $$options{$longOption};
            my $values = $optionArrays{$longOption};
            if (@$values > 1) {
                $$option{hidden}[0] or $report .= "$indent$indent$longOption:\n";
                foreach my $i(0..$#$values){
                    my $value = getReportOptionValue($option, $$values[$i]);
                    $$option{hidden}[0] or $report .= "$indent$indent$indent- $value\n";
                    $taskOptions[$i]{$longOption} = $$values[$i];
                }
            } else {
                my $leftLength = length($longOption);
                my $nSpaces = 15 - $leftLength;
                my $spaces = (" ") x ($nSpaces > 1 ? $nSpaces : 1);
                my $value = getReportOptionValue($option, $$values[0]);
                $$option{hidden}[0] or $report .= "$indent$indent$longOption:$spaces$value\n";
                foreach my $i(1..$nTasks{$action}){
                    $taskOptions[$i-1]{$longOption} = $$values[0];
                }
            }
        }
    }
    
    # print the dependencies
    $report .= $indent."conda:\n";
    $report .= "$indent$indent"."prefix: $$condaPaths{dir}\n";
    foreach my $key(qw(channels dependencies)){
        $report .= "$indent$indent$key:\n";
        $report .= join("\n", map { "$indent$indent$indent- $_" } @{$conda{$key}})."\n";
    } 
    
    # finish up
    $report .= "...\n";
    {taskOptions => \@taskOptions, report => $report};
}
sub getReportOptionValue {
    my ($option, $value) = @_;
    if($$option{type}[0] eq "boolean"){
        $value ? 'true' : 'false';
    } elsif(!defined $value){
        "null";
    } else {
        $value;   
    }
}

1;
