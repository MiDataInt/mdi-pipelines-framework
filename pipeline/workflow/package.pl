use strict;
use warnings;
use File::Copy;
use File::Path qw(remove_tree);

# Called automatically by a running pipeline to assemble a data package, 
# if configured in pipeline.yml. The resulting zip file contains the 
# small(ish) output files of a Stage 1 Pipeline for loading into a 
# Stage 1 App.

#---------------------------------------------------------------
# preparative work
#---------------------------------------------------------------
# load the pipeline config, which might contain the instructions for this script
require "$ENV{JOB_MANAGER_DIR}/lib/main/yaml.pl"; # supports loading multiple YAML from same file
my $pipeline = loadYamlFromString( slurpFile("$ENV{PIPELINE_DIR}/pipeline.yml"), 1 );
my $config = $$pipeline{parsed}[0]{package};

# check for something to do
$config or exit; # pipeline does not export data to Stage 2
$$config{packageAction} or exit;
$$config{packageAction}[0] eq $ENV{PIPELINE_ACTION} or exit; # not the action that exports data
print "writing Stage 2 package file\n";

# load the user option values currently in force
my $options = loadYamlFromString( slurpFile("$ENV{TASK_LOG_FILE}"), 1 );
my $jobConfig  = $$options{parsed}[0];

#---------------------------------------------------------------
# assemble the output yaml that becomes the package manifest
#---------------------------------------------------------------
my $taskConfig = getTaskConfig($$options{parsed}[1]);
my @files; # filled by getOutputFiles
my %contents = (
    uploadType => [$$config{uploadType} ? $$config{uploadType}[0] : $ENV{PIPELINE_NAME}],
    pipeline   => [$ENV{PIPELINE_NAME}],
    action     => [$ENV{PIPELINE_ACTION}],
    task       => $taskConfig,
    files      => getOutputFiles(),
    entropy    => [randomString()] # ensure a unique MD5 hash for every package file
);

#---------------------------------------------------------------
# write config and assembly package zip
#---------------------------------------------------------------
my $packagePrefix = "$ENV{DATA_FILE_PREFIX}.mdi.package";
my $packageFile = "$packagePrefix.zip";
unlink $packageFile;
print "$packageFile\n";
!-d $packagePrefix and mkdir $packagePrefix;
printYAML(\%contents, "$packagePrefix/package.yml");
foreach my $file(@files){
    copy($file, $packagePrefix);
}
system("zip -jr $packagePrefix.zip $packagePrefix");
remove_tree($packagePrefix);
print "\n";

#---------------------------------------------------------------
# fill any task-specific option values into a single task options hash
#---------------------------------------------------------------
sub getTaskConfig {
    my ($taskConfig) = @_;
    $taskConfig or return $jobConfig;
    my $cmd = $$jobConfig{$ENV{PIPELINE_ACTION}};
    foreach my $optionFamily(keys %$cmd){
        foreach my $option(keys %{$$cmd{$optionFamily}}){
            defined $$taskConfig{task}{$option} and
                $$cmd{$optionFamily}{$option} = $$taskConfig{task}{$option};
        }
    }
    $jobConfig;
}

#---------------------------------------------------------------
# parse the automatic and pipeline-specific files to be packaged
#---------------------------------------------------------------
sub getOutputFiles {

    # collect the actual file paths for pipeline-specific files
    my $files = $$config{files};
    foreach my $fileType(keys %$files){
        $$files{$fileType}{file} = [
            parsePackageFile( applyVariablesToYamlValue($$files{$fileType}{file}[0]) )
        ];
    }

    # add automatic files
    $$files{statusFile} = {
        type => ['status-file'],
        file => [ parsePackageFile("$ENV{TASK_PIPELINE_DIR}/$ENV{DATA_NAME}.$ENV{PIPELINE_NAME}.status") ] # to match workflow.sh
    };
    return $files;
}
sub parsePackageFile { # get the file name as recorded in package.yml
    my ($path) = @_;
    push @files, $path;    
    $path =~ m|(.+)/(.+)|;
    $2;
}
sub applyVariablesToYamlValue {
    my ($value) = @_;
    my ($varName, $useType);
    if($value =~ m/\$(\w+)/){
        ($varName, $useType) = ($1, 'plain');
    } elsif($value =~ m/\$\{(\w+)\}/){
        ($varName, $useType) = ($1, 'braces');
    }
    $varName or return $value; # nothing more to do
    defined $ENV{$varName} or die("\nerror creating data package:\nno value found for environment variable '$varName'\n\n");        
    my $target;
    if ($useType eq 'braces') {
        $value =~ s/\{/__OPEN_BRACE__/g; # avoids regex confusion
        $value =~ s/\}/__CLOSED_BRACE__/g;
        $target = "\\\$__OPEN_BRACE__$varName\__CLOSED_BRACE__";  
    } else {
        $target = "\\\$$varName";  
    }
    $value =~ s/$target/$ENV{$varName}/g;    
    return applyVariablesToYamlValue($value);
}

#---------------------------------------------------------------
# print YAML hash to a bare bones .yml file
#---------------------------------------------------------------
sub printYAML {
    my ($yaml, $ymlFile) = @_;
    open our $outH, ">", $ymlFile or throwError("could not open for writing:\n    $ymlFile\n$!");
    sub printYAML_ {
        my ($x, $indentLevel) = @_;
        my $indent = " " x ($indentLevel * 4);
        if (ref($x) eq "HASH") {
            foreach my $key(sort keys %$x){
                print $outH "\n", $indent, "$key:"; # keys
                printYAML_($$x{$key}, $indentLevel + 1);
            }
        } elsif(@$x == 0){     
            print $outH " null";
        } elsif(@$x == 1){ # single keyed values
            my $value = $$x[0];
            defined $value or $value = "null";
            $value eq '' and $value = "null";
            print $outH " $value";
        } else { # arrayed values
            foreach my $value(@$x){ print $outH "\n$indent- $value" }
        }  
    }
    print $outH "---";
    printYAML_($yaml, 0); # recursively write the revised lines
    print $outH "\n\n";
    close $outH;
}

#---------------------------------------------------------------
# utilities
#---------------------------------------------------------------
# read the entire contents of a disk file into memory
sub slurpFile {  
    my ($file) = @_;
    local $/ = undef; 
    open my $inH, "<", $file or die "could not open $file for reading: $!\n";
    my $contents = <$inH>; 
    close $inH;
    return $contents;
}
# generate a random string to ensure variation in package file hash
sub randomString {
    lc(join("", map { sprintf q|%X|, rand(16) } 1 .. 20))
}

1;
