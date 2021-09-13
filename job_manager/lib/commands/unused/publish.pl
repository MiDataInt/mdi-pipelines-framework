use strict;
use warnings;

#========================================================================
# 'publish.pl' create a distribution of instructions, status, log, script and environment files
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw($version %options $qDir $qDataDir $masterFile $masterFileName $statusFile %statusFields $modulesDir);
our (@instrsTree);
my ($pubDir, $replicateDir, $libDir, $utilitiesDir, $commandsDir, $instrsDir, $masterHtmlDir, $imagesDir);
my (@masks, @instrsTreeLinks, %systemCommands, %published, $zipDir, $pubName);
my $maskToDefault = '~';
my $maskToFile = '';
my @reservedWords = qw(exit exitUnless exitIf dieUnless dieIf thread preserve 
                       protect backup publishMask publishDir publishTitle);
my %reservedWords = map { $_ => 1} @reservedWords;
my %rejectJobNames = map {$_=>1} qw(updated qType submitted jobName);
my %utilityCommands = map {$_=>1} qw(checkPredecessors getTaskID checkTaskID checkForData checkPipe snipStream snipFile);
my $iconFile = "$qDir/remote/images/q_icon_35.png";
my $isQExample = $masterFile eq "$qDir/example/q_example.q";
my %scriptingCommands = map { $_ => 1 } qw(perl Rscript awk gawk python);  # known languages that call target scripts that should be published
#========================================================================

#========================================================================
# css page styles
#------------------------------------------------------------------------
my $commonStyle  = 
"a:link{ color: blue; }
a:visited { color: blue; }
a:hover { color: red; }
p {
    font-family: Arial; 
    font-size: 15px;
}";
#------------------------------------------------------------------------
my $selectorStyle =
"$commonStyle
div.icon {
    display:block;
    position:absolute;
    top:0px;
    right:0px;
    margin-right:13px;
    margin-top:5px;
}
select.whte{
    font-family: Arial; 
    font-size: 15px;
    background-color:white;
    color:black;
    width:300;
}";
#------------------------------------------------------------------------
my $masterStyle =
"$commonStyle
td.treeItem{
    font-family: Courier New; 
    font-size: 15px;
    white-space: nowrap;
}
td.statusHeader{
    font-family: Arial; 
    font-size: 13px;
    text-align:center;  
}
td.statusLine{
    font-family: Arial; 
    font-size: 13px; 
}
div.scrolling{
    overflow:auto;
}
div.divider{
    padding-top:12px;
    border-bottom-style:ridge;
    border-width:5px;
    border-color:lightgrey;
}";
#------------------------------------------------------------------------
my $targetStyle =
"$commonStyle
td.fileLine{
    font-family: Courier New; 
    font-size: 15px;
    white-space: nowrap;
}";
#------------------------------------------------------------------------
my $commandStyle =
"$commonStyle
td.commandLine{
    font-family: Courier New; 
    font-size: 15px;
    white-space: nowrap;
}";
#========================================================================

#========================================================================
# client-side javascript
#---------------------------------------------------------------------
my $selectorJavascript =
"function changeCurrentMaster(firstLoad){
    masterFile = document.leftTopForm.masterFile.value;               
    if (undefined == masterFile) { masterFile = document.getElementById('masterFile').options[0] }
    if (undefined != masterFile) {
        top.leftMiddleBottom_.location = masterFile + '.master.html';
        if(firstLoad==0){
            top.right_.location = 'about:blank';
        }
    }
}";
#---------------------------------------------------------------------
my $masterJavascript =
"function sizeMasterDivs(){
    frameHeight = window.innerHeight; 
    leftMiddleBottom = document.getElementById('leftMiddleBottom');     
    leftMiddleLabel = document.getElementById('leftMiddleLabel');     
    leftMiddle = document.getElementById('leftMiddle'); 
    divider = document.getElementById('divider');  
    leftBottomLabel = document.getElementById('leftBottomLabel');     
    leftBottom = document.getElementById('leftBottom');  
    usableHeight = frameHeight - leftMiddleLabel.clientHeight - divider.clientHeight - leftBottomLabel.clientHeight - 75;
    maxLeftMiddleHeight = usableHeight * 0.45;      
    leftMiddle.style.height = ''; 
    leftMiddleHeight = leftMiddle.clientHeight;  
    if(leftMiddleHeight > maxLeftMiddleHeight){
        leftMiddle.style.height = maxLeftMiddleHeight + 'px';  
        leftMiddleHeight = maxLeftMiddleHeight;
    }
    leftBottomHeight = usableHeight - leftMiddleHeight;
    leftBottom.style.height = leftBottomHeight + 'px';             
}
function loadJobFile(file,rowID){
    targetRow = document.getElementById(rowID); 
    table = document.getElementById('jobHistory'); 
    for(i=0; i<table.rows.length; i++) {
        row = table.rows[i];
        if(row == targetRow){
            row.style.backgroundColor = '#dcfac9'; 
        } else {
            row.style.backgroundColor = 'white';
        }
    }
    highlightRow('NO_ROW');
    top.right_.location = file;
}
function highlightRow(targetRow){
    table = document.getElementById('instrsTable'); 
    for(i=0; i<table.rows.length; i++) {
        row = table.rows[i];
        if(row == targetRow){
            row.style.backgroundColor = '#dcfac9'; 
        } else {
            row.style.backgroundColor = 'white';
        }
    }
} 
function filterJobs(file){             
    jobsTable = document.getElementById('jobHistory'); 
    if (undefined != jobsTable) {
        for(i=0; i<jobsTable.rows.length; i++) {
            row = jobsTable.rows[i];
            row.style.backgroundColor = 'white';
            rowID = row.id;
            if(!(rowID == 'header')){
                instrsFile = document.getElementById(rowID + '_instrsFile').value;
                scriptFile = document.getElementById(rowID + '_scriptFile').value;
                if((file == instrsFile || file == scriptFile) || file == 'ALL_JOBS'){
                    row.style.display = '';
                } else {
                    row.style.display = 'none';
                }
            }   
        }    
    }
}";
#========================================================================

#========================================================================
# main execution block
#------------------------------------------------------------------------
sub qPublish { 
    updateStatusQuietly();  
    getOutputFiles('publish');
    parseMasks();  
    createPublishFolders();     
    publishTreeFiles();  # 'tree' is the nested series of instructions and script files that define the pipeline
    publishMasterFile();   
    publishSystemCommands();     
    parseToHtml("$qDir/lib/utilities.sh", "$libDir/utilities/utilities.sh.html", "utilities.sh");
    assembleDistribution();
    print "done\n";
}
#========================================================================

#========================================================================
# handle masking of unnecessary or sensitive information from all published files
# uses might include:
#    masking a common file path, such as "/home/user/data"
#    masking a patient identifier
#------------------------------------------------------------------------
sub parseMasks {
    $options{mask} or return;
    @masks = split(",", $options{mask});
    @masks = sort {length $b <=> length $a} @masks;  # always process longer masks before shorter ones
    foreach my $mask(@masks){ $mask =~ s/\//\\\//g }
}
sub maskString {
    my ($str, $maskTo) = @_;
    defined $maskTo or $maskTo = $maskToDefault;
    foreach my $mask(@masks){ $$str =~ s/$mask/$maskTo/g }
}
#========================================================================

#========================================================================
# output paths
#------------------------------------------------------------------------
sub createPublishFolders {
    $pubDir = $options{'out-dir'};
    $pubDir or die "option '--out-dir' or instruction 'publishDir' is required for command 'q publish'\n";
    $pubDir =~ m|^/.+| or die "--out-dir/publishDir must be provided as absolute, not relative, path\n";
    -e $pubDir and !(-d $pubDir) and die "$pubDir already exists but is not a directory\n";
    $pubDir =~ m|(.+)/(.+)$| and ($zipDir, $pubName) = ($1, $2);
    $replicateDir = "$pubDir/instructions";  # the replicate of the actual instructions files
    $libDir = "$pubDir/lib";  # the html library  
    $utilitiesDir = "$libDir/utilities";       
    $commandsDir = "$libDir/systemCommands";    
    $instrsDir = "$libDir/instructions";
    $masterHtmlDir = "$libDir/$masterFileName";
    $imagesDir = "$libDir/images";
    qx|mkdir -p $pubDir|; 
    mkdir $replicateDir; 
    mkdir $libDir;  
    mkdir $utilitiesDir; 
    mkdir $commandsDir; 
    mkdir $instrsDir;     
    mkdir $masterHtmlDir; 
    mkdir $imagesDir; 
}
#========================================================================

#========================================================================
# publish pipeline-level instructions files and target scripts
#------------------------------------------------------------------------
sub publishTreeFiles {  # recover and process instructions and scripts that define the pipeline
    print "publishing $masterFile\n";
    my (%linked, @linkKeys);
    createInstrsTreeLink(\%linked, "", 0, "", 'ALL_JOBS', 'ALL_JOBS');  # instrs link to show all jobs in status pane; others will filter the status pane
    foreach my $treeRef(@instrsTree){
        my ($threadLevel, $file, $isEmbedded) = @$treeRef;
        my ($relativePath, $filename);
        if($isEmbedded){
            ($relativePath, $filename) = ("", $file); 
        } else {
            $file =~ m|^/.+| or die "publishInstrsFiles; $file was not an absolute path\n";  # internal check, should always pass if q is working
            ($relativePath, $filename) = parseFileString($file);
            publishFile($file, $relativePath, $filename);
        }
        @linkKeys = (@linkKeys[0..$threadLevel-1], $filename);
        @linkKeys = map { $_ ? $_ : "" } @linkKeys;
        my $linkKey = join("/", @linkKeys);  
        createInstrsTreeLink(\%linked, $linkKey, $threadLevel, $relativePath, $filename, $file, $isEmbedded);           
    } 
}
sub parseFileString {
    my ($file) = @_;
    maskString(\$file, $maskToFile);     
    $file =~ m|^/(.+)| and $file = $1;       
    my ($relativePath, $filename) = ('', $file);
    $file =~ m|(.*/)(.+)$| and ($relativePath, $filename) = ($1, $2);
    return ($relativePath, $filename);
}
sub publishFile { 
    my ($file, $relativePath, $filename) = @_;
    $published{$file} and return;
    my $repDir = "$replicateDir/$relativePath";
    qx|mkdir -p $repDir|;
    qx|cp $file $repDir|;        
    my $htmlDir = "$instrsDir/$relativePath";
    qx|mkdir -p $htmlDir|;
    parseToHtml($file, "$htmlDir$filename.html", $filename, ($relativePath =~ tr/\///));  # create html parsed versions for web display
    $published{$file}++;
}
sub createInstrsTreeLink { # collect information used later for master invocation tree
    my ($linked, $linkKey, $threadLevel, $relativePath, $filename, $file, $isEmbedded) = @_;
    $linkKey ne "environment.q" and $$linked{$linkKey} and return;  # non-environment files only placed in the tree once
    my $extender = $threadLevel ? "|__" : "";
    my $spacer = '***' x ($threadLevel - 1).$extender; 
    if($isEmbedded){
        push @instrsTreeLinks, [$linkKey, "$spacer$filename"];     
    } else {
        my $href = $filename eq 'ALL_JOBS' ? "about:blank" : "../lib/instructions/$relativePath$filename.html";
        my $label = $file =~ m|^$modulesDir/(.+)| ? "q::$1" : $filename;
        push @instrsTreeLinks, [$linkKey, "$spacer<a target=right_ href=$href onclick=filterJobs('$file')>$label</a>"];      
    }    
    $$linked{$linkKey}++;
}
#========================================================================

#========================================================================
# publish status, log, script and environment files associated with master
#------------------------------------------------------------------------
sub publishMasterFile {
    my $htmlFile = "$libDir/$masterFileName.master.html";
    open my $outH, ">", $htmlFile or die "could not open $htmlFile for writing $!\n";
    print $outH 
"<html>   
<head>
<style>
$masterStyle
</style>
<script>
$masterJavascript
</script>
</head>
<body onload=sizeMasterDivs() onresize=sizeMasterDivs()>
<div id=leftMiddleBottom>\n",
getInstrsTreeDiv(),
"<div id=divider class=divider></div>",
getStatusDiv(),
"</div>
</body>
</html>\n";
    close $outH;
}
#------------------------------------------------------------------------
sub getInstrsTreeDiv { # html hyperlink tree reflecting the invocation/qsub structure of the current master instructions file
    return join("",
"<div id=leftMiddleLabel>
<p><b>Instructions and Scripts</b></p>
</div>
<div id=leftMiddle class=scrolling>
<table id=instrsTable>\n",
getInstrsTreeRows(),
"</table>
</div>\n");
}
sub getInstrsTreeRows { # the html table rows containing the invocation/qsub hyperlinks
    my @tree;
    fillJobTreeLinks(\my@treeLinks);
    my $nLinks = scalar(@treeLinks);
    my @is = reverse(0..($nLinks-1));
    foreach my $i(@is){
        my $link = $treeLinks[$i];
        if($link =~ m/^(\**)\|/){
            my $leader = length($1);
            my @js = reverse(0..($i-1));
            for my $j(@js){
                $treeLinks[$j] =~ m/(.{$leader})(.)(.*)/;
                $2 eq '*' or last;
                $3 or $3 = "";
                $treeLinks[$j] = "$1|$3"; 
            }
        } 
        $link =~ s/\*/&nbsp/g;
        $link =~ m/JOB:/ and $link =~ s/JOB\://g and $link =~ s/href/class=job href/;
        $link = "<tr id=$i onclick=highlightRow(this)><td class=treeItem>$link</td></tr>\n";  
        unshift @tree, $link;
    }
    return join("", @tree);
}
sub fillJobTreeLinks { 
    my ($treeLinks) = @_;
    foreach my $instr(@instrsTreeLinks){
        my ($instrsKey, $link) = @$instr;
        push @$treeLinks, $link;
    }
}
#------------------------------------------------------------------------
sub getStatusDiv {
    my @cells = $options{long} ?
                qw(jobName jobID job predecessors array start_time walltime maxvmem):
                qw(jobName job predecessors array walltime maxvmem);
    my $html = join("",
"<div id=leftBottomLabel>
<p><b>Job History</b></p>
</div>
<div id=leftBottom class=scrolling>
<table id=jobHistory border=1 cellpadding=0 cellspacing=0>\n",
getStatusHeader() );    
    open my $statusFileH, "<", $statusFile or return;
    while(my $line = <$statusFileH>){
        chomp $line;
        $line or next;
        my @line = split("\t", $line);
        my $jobName = $line[$statusFields{jobName}];
        $jobName or next;
        $jobName =~ s/\s+$//;
        $rejectJobNames{$jobName} and next;
        my $exit_status = $line[$statusFields{exit_status}];
        defined $exit_status or next;
        my $jobID = $line[$statusFields{jobID}];
        my $lFile = publishLogFile($line[$statusFields{qType}], $jobName, $line[$statusFields{jobID}], $line[$statusFields{array}]);
        my $scFile = publishScriptFile($line[$statusFields{targetScript}], $jobID);
        my $envFile = publishEnvironmentFile($line[$statusFields{qType}], $jobID);
        my $rowID = "$jobName\_$jobID";
        $html .= 
"<tr id=$rowID>
<input type=hidden id=$rowID\_instrsFile value=$line[$statusFields{instrsFile}] >
<input type=hidden id=$rowID\_scriptFile value=$line[$statusFields{scriptFile}] >
<td class=statusLine>&nbsp<a href=javascript:loadJobFile(\"$lFile\",\"$rowID\")>log</a>&nbsp</td>
<td class=statusLine>&nbsp<a href=javascript:loadJobFile(\"$scFile\",\"$rowID\")>script</a>&nbsp</td>
<td class=statusLine>&nbsp<a href=javascript:loadJobFile(\"$envFile\",\"$rowID\")>env</a>&nbsp</td>\n";
        foreach my $cellName(@cells){
            my $cell = $line[$statusFields{$cellName}];
            $cellName eq 'jobName' and maskString(\$cell);
            $cellName eq 'jobName' and $cell =~ s/\s+$//;
            $cellName eq 'array' and $cell = $cell ? '@' : "";
            (defined $cell and length($cell)) or $cell = '&nbsp';
            $cell =~ s/\s/&nbsp/g;
            $cell =~ s/;/&#59;/g;
            $html .= 
"<td class=statusLine>&nbsp$cell&nbsp</td>\n";
        }
        $html .= 
"</tr>\n";
    }
    $html .= 
"</table>
</div>\n";
    close $statusFileH;
    return $html;
}
sub getStatusHeader {
    my $html =
"<tr id=header>
<td colspan=3 class=statusHeader><b>&nbspshow&nbsp</b></td>
<td colspan=1 class=statusHeader><b>&nbspjob_name&nbsp</b></td>\n";
    $options{long} and $html .=
"<td colspan=1 class=statusHeader><b>&nbspjob_ID&nbsp</b></td>\n";
    $html .=
"<td colspan=3 class=statusHeader><b>&nbspjob_chain&nbsp</b></td>\n";
    $options{long} and $html .=
"<td colspan=1 class=statusHeader><b>&nbspstart_time&nbsp</b></td>\n";
    $html .=
"<td colspan=1 class=statusHeader><b>&nbsphh:mm:ss&nbsp</b></td>
 <td colspan=1 class=statusHeader><b>&nbspRAM&nbsp</b></td>
</tr>\n";  
    return $html;
}
#------------------------------------------------------------------------
sub publishLogFile { # create html for specific job log file
    my($qType, $jobName, $jobID, $array) = @_;
    my $logFiles = getLogFiles($qType, $jobName, $jobID, $array);    
    if(scalar(@$logFiles)){
        $$logFiles[0] =~ m|$qDataDir/(.+/)(.+\.o$jobID).*$|;
        my ($relativePath, $filename) = ($1, $2);        
        my @contents;
        foreach my $logFile(@$logFiles){
            -e $logFile or next;
            my $contents = slurpFile($logFile);
            $contents =~ s|\e\[H\e\[2J||g;
            push @contents, $contents;
        }
        my $contents = join("\n#".('='x100)."\n\n",@contents);
        return publishJobFile(\$contents, $relativePath, $filename); 
    }
    return "";
}
sub publishScriptFile { # create html for specific job q-parsed script
    my($targetScript, $jobID) = @_;
    $targetScript =~ m|$qDataDir/(.+/)(.+)$|;
    my $relativePath = $1;
    my $filename = "$jobID.sh";  # rename to script to simpler version now that jobID is available
    return publishJobFile($targetScript, $relativePath, $filename);  
}
sub publishEnvironmentFile {
    my($qType, $jobID) = @_;
    my $envFile = getEnvFile($qType, $jobID);
    my $contents;
    if(open my $inH, "<", $envFile){
        while(my $line = <$inH>){ 
            $line = "_IS_ENVIRONMENT_LINE_$line";
            $contents .= $line;
        }
    }
    $envFile =~ m|$qDataDir/(.+/)(.+)$|;
    my ($relativePath, $filename) = ($1, $2);        
    return publishJobFile(\$contents, $relativePath, $filename);
}
sub publishJobFile {
    my($file, $relativePath, $filename) = @_;
    my $htmlDir = "$masterHtmlDir/$relativePath";
    qx|mkdir -p $htmlDir|;
    parseToHtml($file, "$htmlDir$filename.html", $filename, ($relativePath =~ tr/\///)); 
    return "../lib/$masterFileName/$relativePath$filename.html";
}
#========================================================================

#========================================================================
# highlighted html parsing for instructions file/script/etc. content files
#------------------------------------------------------------------------
sub parseToHtml{
    my ($sourceFile, $htmlFile, $fileName, $upLevels) = @_;
    my $targetUp = "../";
    defined $upLevels and $targetUp .= '../' x $upLevels;
    open my $inH, "<", $sourceFile or die "could not open $sourceFile for reading: $!\n";
    open my $outH, ">", $htmlFile or die "could not open $htmlFile for writing $!\n";
    print $outH 
"<html>
<head>
<style>
$targetStyle
</style>
</head>
<body>
<p><b><u>$fileName</u></b><br></p>
<table border=0 cellpadding=0 cellspacing=0>\n";
    while (my $line = <$inH>){
        my $parsedLine = parseFileLine($sourceFile, $line, $targetUp);
        print $outH 
"<tr><td class=fileLine>$parsedLine</td></tr>\n";
    }
    print $outH
"</table>
</body>
</html>\n";
    close $inH;
    close $outH;
}
#-----------------------------------------------------------------------
sub parseFileLine {
    my ($sourceFile, $line, $targetUp) = @_;
    chomp $line;
    !$options{long} and $line =~ m|^(q: execution started\:)| and $line = "$1 ~";
    !$options{long} and $line =~ m|^(q: execution ended\:)| and $line = "$1 ~";
    my $unmasked = $line;
    maskString(\$line);
    my @line = split(/\s+/, $line);        
    $line =~ s/\s/&nbsp/g;
    $line =~ m/^<(file.*)>/ and $line = "\&lt$1\&gt";
    $line =~ m/^<(\/file)>/ and $line = "\&lt$1\&gt";
    if($line =~ m/^(\w+)&nbsp(.*)/ or $line =~ m/^(\w+)$/){
        my ($command, $arguments) = ($1, $2);
        $arguments or $arguments = "";
        if($utilityCommands{$command}){
            $line = "<a target=right_ href=$targetUp"."../lib/utilities/utilities.sh.html>$command</a>&nbsp$arguments";
        } elsif($command eq 'invoke'){
            getTargetLink($sourceFile, \$line, \@line, $unmasked, 1, $targetUp); 
        } elsif($command eq 'qsub'){
            getTargetLink($sourceFile, \$line, \@line, $unmasked, 1, $targetUp); 
        } elsif($command eq 'source'){
            $unmasked =~ m|^source\s+\"(.+)\"| and $unmasked = "source $1";
            getTargetLink($sourceFile, \$line, \@line, $unmasked, 1, $targetUp, 1);      
        } elsif($reservedWords{$command}){
            #do nothing
        } elsif(isShellCommand($command)){
            $systemCommands{$command}++;
            $line[0] = "<a target=right_ href=$targetUp"."systemCommands/$command.html>$command</a>";
            if($scriptingCommands{$command}){
                getTargetLink($sourceFile, \$line, \@line, $unmasked, 1, $targetUp, 1);              
            } else {
                $line = "$line[0]&nbsp$arguments";
            }
        } elsif($line =~ m/^_IS_ENVIRONMENT_LINE_(.+)/) {
            $line = $1;
            $line =~ m|^(.+?)&nbsp=&nbsp(.*)| and $line = "$1&nbsp&nbsp</td><td class=fileLine>$2";
        } 
    }
    $line =~ s/(\$\w+)/<font color=maroon>$1<\/font>/g;
    $line =~ s/(#.*)/<font color=darkgreen>$1<\/font>/g;
    $line =~ s/;/&#59;/g;
    ($line and length($line)) or $line = '&nbsp';
    return $line;
}
sub getTargetLink { # create a link to a target file called within a file via invoke, qsub, source or scripting language
    my($sourceFile, $line, $lineArray, $unmasked, $targetIndex, $targetUp, $publish) = @_;
    my @unmasked = split(/\s+/, $unmasked);
    $targetIndex or $targetIndex = $#unmasked;
    my $parsedFile = $unmasked[$targetIndex];    
    replaceItemsVars(\$parsedFile);
    $isQExample and $parsedFile = "$qDir/example/$parsedFile";    
    my $targetFile;
    my $sourceDir = "__XXX__";
    $sourceFile =~ m|(.+)/| and $sourceDir = $1;
    my $relativeFile = "$sourceDir/$parsedFile";    
    my $moduleFile = "$modulesDir/$parsedFile";
    if(-e $parsedFile){
        $targetFile = $parsedFile;
    } elsif(-e $relativeFile) {
        $targetFile = $relativeFile; 
    } elsif(-e $moduleFile) {
        $targetFile = $moduleFile;
    }
    if($targetFile and -e $targetFile){
        my ($relativePath, $filename) = parseFileString($targetFile);
        if($targetFile eq "$qDir/lib/utilities.sh"){
            $$lineArray[$targetIndex] = "<a target=right_ href=$targetUp"."utilities/utilities.sh.html>$$lineArray[$targetIndex]</a>"; 
        } else {
            $$lineArray[$targetIndex] = "<a target=right_ href=$targetUp"."instructions/$relativePath$filename.html>$$lineArray[$targetIndex]</a>"; 
            $publish and publishFile($targetFile, $relativePath, $filename);
        }
    }
    $$line = join('&nbsp', @$lineArray);
}
sub replaceItemsVars { # limited variable replacement to help find called target files
    my ($item) = @_;
    my @varChunks = split(/\$/, $$item);
    my $leader = shift @varChunks;
    scalar(@varChunks) or return; # nothing to replace
    foreach my $i(0..$#varChunks){
        $varChunks[$i] =~ m/^(\w+)(.*)$/ or next;
        my ($var, $rest) = ($1, $2);
        defined $ENV{$var} or next;
        defined $rest or $rest = '';
        $varChunks[$i] = "$ENV{$var}$rest";
    }
    $$item = join("", $leader, @varChunks); 
}
#========================================================================

#========================================================================
# publish information on system commands that were called by pipeline
# KNOWN LIMITATION: as implemented, target version may have changed between
# the time the command was queued and the time that q publish was called.
#------------------------------------------------------------------------
sub publishSystemCommands { # html file containing version and help information for the command
    foreach my $systemCommand(keys %systemCommands){  # list contains any command encountered in any instructions file or target script
        my $htmlFile .= "$commandsDir/$systemCommand.html";
        open my $outH, ">", $htmlFile or die "could not open $htmlFile for writing $!\n";
        print $outH 
"<html>
<head>
<style>
$commandStyle
</style>
</head>
<body>\n";
        printTargetInfoHtml($outH, $systemCommand, '--version');   
        printTargetInfoHtml($outH, $systemCommand, '--help'); 
        print $outH
"</body>
</html>\n"; 
        close $outH; 
    }                   
}
sub printTargetInfoHtml { # programs report their own version and help from the command line
    my ($outH, $systemCommand, $option) = @_;
    my $data = qx/$systemCommand $option 2>\&1/; 
    print $outH 
"<p><b><u>$systemCommand $option</u></b><br>
<table border=0 cellpadding=0 cellspacing=0>\n";
    if(defined $data){
        foreach my $line(split("\n", $data)){
            chomp $line;
            $line =~ s/\s/&nbsp/g;
            $line =~ s/;/&#59;/g;        
            (defined $line and length($line)) or $line = '&nbsp';
            print $outH 
"<tr><td class=commandLine>$line</td></tr>\n";
        }
    }
    print $outH 
"</table>\n";
}
#========================================================================

#========================================================================
# create master html output
#------------------------------------------------------------------------
sub assembleDistribution {
    print "creating html\n";
    my $title = $pubDir;
    $title =~ m|.*/(.+)$| and $title = $1;
    $options{title} and $title = $options{title};    
    my $mainFile = "$title.html";
    $mainFile =~ s/\s+/_/g;    
    $title eq 'q_publish' and $title = '';
    my $pageTitle = $title ? $title : 'Publish';    
    $title and $title .= "<br>";    
    my $leftTopFile = "leftTop.html";  
    my $rightStartFile = getRightStartFile();
    my $mainHtml = getMainHtml($pageTitle, $leftTopFile, $rightStartFile); 
    printToFile($mainHtml, "$pubDir/$mainFile"); 
    my $leftTopHtml = getLeftTopHtml($libDir, $title, $rightStartFile); # must come last
    printToFile($leftTopHtml, "$libDir/$leftTopFile");
    if($options{zip}){
        print "creating publication report tarball\n";
        print qx|cd $zipDir ; tar -czf $pubName.tar.gz $pubName|; 
        print "    $zipDir/$pubName.tar.gz\n";           
    }
}
sub getRightStartFile {
    $options{'intro-file'} or return "help.html"; 
    -e $options{'intro-file'} or die "could not find file $options{'intro-file'}\n";
    my $filename = $options{'intro-file'};
    $options{'intro-file'} =~ m|.*/(.+)$| and $filename = $1;
    qx|cp $options{'intro-file'} $libDir/$filename|;
    return $filename;
}
sub printToFile {
    my ($text, $file) = @_;
    open my $outH, ">", $file or die "could not open $file for writing: $!\n";
    print $outH $text;
    close $outH;
}
#------------------------------------------------------------------------
sub getMainHtml { # the top level html for the q_publish report
    my ($pageTitle, $leftTopFile, $rightStartFile) = @_;
    my $leftWidth = $options{long} ? '675px' : '500px';
    return  # left middle and bottom will be loaded dynamically by javascript changeCurrentMaster 
"<html>
<head>
<title>q: $pageTitle</title>
</head>
<frameset cols=$leftWidth,*>
    <frameset rows=110px,*>
        <frame name=leftTop_ src=lib/$leftTopFile>
        <frame name=leftMiddleBottom_ src=about:blank >
    </frameset>
    <frame name=right_ src=lib/$rightStartFile>
</frameset>
</html>\n";
}
#------------------------------------------------------------------------
sub getLeftTopHtml { # the html for the upper left browser frame that provides master navigation
    my ($libDir, $title, $rightStartFile) = @_;
    my $masterSelect = getMasterInstrsSelector($libDir);
    qx|cp $qDir/lib/help.html $libDir|;
    $options{'intro-file'} and $title = "<a target=right_ href=$rightStartFile>$title</a>";
    qx|cp $iconFile $imagesDir|;
    return 
"<html>
<head>
<style>
$selectorStyle
</style>
<script>
$selectorJavascript
</script>
</head>
<body onload=changeCurrentMaster(1)>
<div class=icon>
<a target=q_frame href=http://tewlab.org/q>
<img src=images/q_icon_35.png border=0>
</a>
</div>
<p>
<b>$title"."Pipeline Report</b>&nbsp&nbsp
<a target=right_  href=\"help.html\">Help</a>
</p>
<form name=leftTopForm>
<p>$masterSelect&nbsp&nbsp</p>
</form>
</body>
</html>\n";
}
sub getMasterInstrsSelector { # populate a drop-down with ALL master files published in outDir (not just the current one)
    my ($libDir) = @_;
    my @options;
    foreach my $masterFile(sort {$a cmp $b} <$libDir/*.master.html>){
        $masterFile =~ m|.+/(.+).master.html$| and $masterFile = $1;
        push @options, "<option>$masterFile</option>";
    }
    my $size = scalar(@options);
    $size = ($size > 10) ? 10 : $size;
    my $select = join("", @options);
    return "Master&nbsp&nbsp<select name=masterFile size=1 class=whte onchange=changeCurrentMaster(0)>$select</select>\n";
}
#========================================================================

1;

