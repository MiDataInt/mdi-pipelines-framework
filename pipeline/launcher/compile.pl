use strict;
use warnings;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;

# subs for compiling executables found as pipeline scripts
# at present only the Rust language and compiler (cargo) are supported

use vars qw(@args $environmentsDir $config %optionArrays $pipelineDir $sharedDir);

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
    my $loadCommand = applyVariablesToYamlValue($$configYml{conda}{'load-command'}[0], \%ENV);
    my $profileScript = applyVariablesToYamlValue($$configYml{conda}{'profile-script'}[0], \%ENV);
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
    
    # check the path where executables are deposited
    my $mdiBinDir = "$ENV{MDI_DIR}/bin";
    -d $mdiBinDir or mkdir $mdiBinDir or die "could not create $mdiBinDir: $!\n";

    # list and, if requested, create the required executables
    foreach my $language(keys %compilationTargets){
        foreach my $targetName(keys %{$compilationTargets{$language}}){
            my $target = $compilationTargets{$language}{$targetName};
            my $binPath = $$target{srcDir};
            $binPath =~ s/^$ENV{MDI_DIR}//;
            $binPath = "$mdiBinDir$binPath";
            my $targetBin = "$binPath/$targetName";
            my $exists = -e $targetBin ? "exists" : "does not exist";
            print "\n".join("\n", 
                "language: $language",
                "target:   $targetName",
                "version:  $$target{targetVersion}",
                "source:   $$target{scrDir}",
                "binary:   $targetBin",
                $exists
            ). "\n";
        }
    }
}
sub loadCompilationTargets {
    my ($subjectAction, $compilationTargets) = @_;
    my $cmd = getCmdHash($subjectAction) or return;
    $$cmd{compilationTargets} or return;
    $$cmd{compilationTargets}[0] or return;
    foreach my $compilationTarget(@{$$cmd{compilationTargets}}){
        my ($language, $relPath) = split('::', $compilationTarget); # expects rust::crates/xyz, in pipeline or shared directory
        $relPath or throwError("pipeline configuration error\nmalformed compilationTarget (expected language::relPath):\n    $compilationTarget");
        $language = lc($language);
        if($language eq "rust"){
            my $cargoToml = "$pipelineDir/$relPath/Cargo.toml";
            -f $cargoToml or $cargoToml = "$sharedDir/$relPath/Cargo.toml";
            -f $cargoToml or throwError("pipeline configuration error\nCargo.toml not found:\n    $compilationTarget");
            my $scrDir = dirname $cargoToml;
            my $targetName = basename $scrDir;
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
            $$compilationTargets{$language}{$targetName} = {
                targetName    => $targetName,
                relPath       => $relPath,
                scrDir        => $scrDir,
                targetVersion => $targetVersion
            };
        } else {
            throwError("pipeline configuration error\nunsupported compilation language:\n    $compilationTarget");
        }
    }
}

1;
