use strict;
use warnings;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;

# subs for compiling executables found as pipeline scripts
# at present only the Rust language and compiler (cargo) are supported

use vars qw(@args $environmentsDir $config %optionArrays $pipelineSuite $pipelineName $pipelineDir $sharedDir);

#------------------------------------------------------------------------------
# if missing, compile executable binaries defined by pipeline scripts
# use hashes of those scripts to know whether a specific version has been compiled TODO use suite versions?
#------------------------------------------------------------------------------
sub showCompileExecutables {
    my ($create, $force, $noMamba) = @_;
    my $cmds = $$config{actions}; 
    my @orderedActions = sort { $$cmds{$a}{order}[0] <=> $$cmds{$b}{order}[0] } keys %$cmds;

    # find all unique compilation targets
    my (%compilationTargets,  $configYml);
    foreach my $subjectAction(@orderedActions){
        $$cmds{$subjectAction}{universal}[0] and next;
        my $cmd = getCmdHash($subjectAction);
        loadActionOptions($cmd);
        $configYml = assembleCompositeConfig($cmd, $subjectAction);
        setOptionsFromConfigComposite($configYml, $subjectAction);
        loadCompilationTargets($subjectAction, \%compilationTargets);
    }

    # locate the script that must be sourced to allow 'conda activate' to be called from scripts
    # see: https://github.com/conda/conda/issues/7980
    my($loadCommand, $profileScript);
    if($create){
        $loadCommand = applyVariablesToYamlValue($$configYml{conda}{'load-command'}[0], \%ENV);
        $profileScript = applyVariablesToYamlValue($$configYml{conda}{'profile-script'}[0], \%ENV);
        if(!$profileScript or $profileScript eq 'null'){
            my $loadCommand = $loadCommand ? $loadCommand : "echo";
            my $condaBasePath = qx|$loadCommand 1>/dev/null 2>/dev/null; conda info --base|;
            chomp $condaBasePath;
            $profileScript = "$condaBasePath/etc/profile.d/conda.sh";
        }
        
        # determine if the server requires us to load conda (if not, it must be always available)
        if(!$loadCommand or $loadCommand eq 'null'){
            $loadCommand = "# using system conda";
        }
    }

    # check the path where executables are deposited
    my $mdiBinDir = "$ENV{MDI_DIR}/bin";
    -d $mdiBinDir or mkdir $mdiBinDir or die "could not create $mdiBinDir: $!\n";

    # list and, if requested, create the required executables
    foreach my $language(keys %compilationTargets){
        foreach my $targetName(keys %{$compilationTargets{$language}}){
            my $targetBinDir = "$mdiBinDir/$pipelineSuite/$pipelineName/$targetName";
            my $exists = -d $targetBinDir ? "exists" : "does not exist";
            my $target = $compilationTargets{$language}{$targetName};
            foreach my $binary(keys %$target){
                my $target = $$target{$binary};
                print "\n".join("\n", 
                    "language: $language",
                    "target:   $targetName",
                    "binary:   $binary",
                    "version:  $$target{targetVersion}",
                    "fromDir:  $$target{compileBaseDir}",
                    "toDir:    $targetBinDir",
                    $exists
                ). "\n";
                if($create and ($exists ne "exists" or $force)){
                    print "compiling...\n";
                    if($language eq "rust"){
                        my $binOption = $binary eq "*" ? "--bins" : "--bin $binary";
                        my $cmd = "cd $$target{compileBaseDir}; cargo build $binOption --release --target-dir $targetBinDir";
                        print "$cmd\n";
                        # system($cmd) == 0 or die "could not compile $targetName: $!\n";
                        # -e "$$target{srcDir}/target/release/$targetName" or die "could not find compiled binary: $!\n";
                        # system("cp $$target{srcDir}/target/release/$targetName $targetBin") == 0 or die "could not copy compiled binary: $!\n";
                    } else {
                        die "unsupported language: $language\n";
                    }
                }
            }
        }
    }
}
sub loadCompilationTargets {
    my ($subjectAction, $compilationTargets) = @_;
    my $cmd = getCmdHash($subjectAction) or return;
    $$cmd{compilationTargets} or return;
    $$cmd{compilationTargets}[0] or return;
    foreach my $compilationTarget(@{$$cmd{compilationTargets}}){
        my ($language, $relPath, $binary) = split('::', $compilationTarget); # expects rust::crates/xyz, in pipeline or shared directory
        $relPath or throwError("pipeline configuration error\nmalformed compilationTarget (expected language::relPath::binary):\n    $compilationTarget");
        $language = lc($language);
        if($language eq "rust"){
            $binary or throwError("pipeline configuration error\nmalformed compilationTarget (expected language::relPath::binary):\n    $compilationTarget");
            # - rust::crates/<crate_name>::<binary_name> # compile a specific binary
            # - rust::crates/<crate_name>::* # compile all binaries including .../src/main.rs, .../src/bin/*.rs, and .../src/bin/*/main.rs
            my $cargoToml = "$pipelineDir/$relPath/Cargo.toml";
            -f $cargoToml or $cargoToml = "$sharedDir/$relPath/Cargo.toml";
            -f $cargoToml or throwError("pipeline configuration error\nCargo.toml not found:\n    $compilationTarget");
            my $compileBaseDir = dirname $cargoToml;
            my $crateName = basename $compileBaseDir;
            my $targetVersion;
            open my $fh, '<', $cargoToml or die "could not open $cargoToml: $!\n";
            while(<$fh>){
                if(/^\s*version\s+=\s+"(.+)"/){
                    $targetVersion = $1;
                    last;
                }
            }
            $targetVersion or throwError("pipeline configuration error\nCargo.toml does not specify a version:\n    $compilationTarget");
            close $fh;
            $$compilationTargets{$language}{$crateName}{$binary} = {
                language        => $language,
                crateName       => $crateName,
                binary          => $binary,
                relPath         => $relPath,
                compileBaseDir  => $compileBaseDir,
                targetVersion   => $targetVersion,
            };
        } else {
            throwError("pipeline configuration error\nunsupported compilation language:\n    $compilationTarget");
        }
    }
}

1;
