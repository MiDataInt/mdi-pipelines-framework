use strict;
use warnings;
use File::Copy;
use File::Path qw(remove_tree);

# called automatically by running pipeline to
# assemble a Portal output package, if configured in pipeline.yml
# resulting zip file contains the small(ish) output files of a stage 1 pipeline

#---------------------------------------------------------------
# preparative work
#---------------------------------------------------------------
# load the pipeline config, with portal output definition
require "$ENV{JOB_MANAGER_DIR}/lib/main/yaml.pl"; # supports loading multiple YAML from same file
my $pipeline = loadYamlFromString( slurpFile("$ENV{PIPELINE_DIR}/pipeline.yml"), 1 );
my $portalConfig = $$pipeline{parsed}[0]{portalPackage};

# check for something to do
$portalConfig or exit; # pipeline does not export data to the Portal
$$portalConfig{packageCommand} or exit;
$$portalConfig{packageCommand}[0] eq $ENV{PIPELINE_COMMAND} or exit; # not the command that exports data
print "writing Portal package file\n";

# load the user option values in force
my $options = loadYamlFromString( slurpFile("$ENV{TASK_LOG_FILE}"), 1 );
my $jobConfig  = $$options{parsed}[0];

#---------------------------------------------------------------
# assemble the output yaml that becomes the package manifest
#---------------------------------------------------------------
my $taskConfig = getTaskConfig($$options{parsed}[1]);
my @files; # filled by getOutputFiles
my %contents = (
    uploadType => [$$portalConfig{uploadType} ? $$portalConfig{uploadType}[0] : $ENV{PIPELINE_NAME}],
    pipeline   => [$ENV{PIPELINE_NAME}],
    command    => [$ENV{PIPELINE_COMMAND}],
    task       => $taskConfig,
    files      => getOutputFiles(),
    entropy    => [randomString()]
);

#---------------------------------------------------------------
# write config and assembly package zip
#---------------------------------------------------------------
my $packagePrefix = "$ENV{DATA_FILE_PREFIX}.midata.package";
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
    my $cmd = $$jobConfig{$ENV{PIPELINE_COMMAND}};
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
    my $files = $$portalConfig{files};
    foreach my $fileType(keys %$files){
        $$files{$fileType}{file} = [
            parsePackageFile( applyVariablesToYamlValue($$files{$fileType}{file}[0]) )
        ];
    }
    # add automatic files
    $$files{statusFile} = {
        type => ['status-file'],
        file => [ parsePackageFile("$ENV{LOG_FILE_PREFIX}.$ENV{PIPELINE_NAME}.status") ]
    };
    $$files{manifestFile} = {
        type => ['manifest-file'],
        file => [ $$taskConfig{$ENV{PIPELINE_COMMAND}}{AGC} ?
                  parsePackageFile($$taskConfig{$ENV{PIPELINE_COMMAND}}{AGC}{'manifest-file'}[0]) :
                  'null' ]
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
    defined $ENV{$varName} or die("\nerror packaging for portal:\nno value found for environment variable '$varName'\n\n");        
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
# generate a random string to ensure variation in package file signature
sub randomString {
    lc(join("", map { sprintf q|%X|, rand(16) } 1 .. 20))
}

1;

#sub getOutputOptions {
#    my $options = $$pipeline{portalPackage}{options};
#    my %options = map { $_ => getOptionValue($_) } @$options;
#    return \%options;
#}
#sub fillEnvVars {
#    my ($value) = @_;
#    $value =~ m/\$()   (.*)\{(.+?)\}(.*)/ or return $value;
#    fillEnvVars($1.getOptionValue($2).$3);
#}
#sub getOptionValue {
#    my ($option) = @_;
#    $option =~ s/-/_/g;
#    $ENV{uc($option)} || 'null';
#}
#sub getManifest {
#    my $manifest = getOptionValue('manifest-file');
#    $manifest eq 'null' and return {manifest => $manifest};
#    # do work to parse and handle the manifest
#}

