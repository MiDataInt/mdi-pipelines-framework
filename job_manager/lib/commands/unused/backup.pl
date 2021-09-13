use strict;
use warnings;

#========================================================================
# 'backup.pl' uses rsync to make data output archives and restore from them
#========================================================================

#========================================================================
# define variables
#------------------------------------------------------------------------
use vars qw(%options $getOutputFiles);
our %backupDirs;
#========================================================================

#========================================================================
# main execution blocks
#------------------------------------------------------------------------
sub qBackup { 
    getOutputFiles('backup');
    callRsync('backed up', 'backing up');
}
sub qRestore { 
    getOutputFiles('restore');
    callRsync('restored', 'restoring', 1);
}
#========================================================================

#========================================================================
# rsync control subs
#------------------------------------------------------------------------
sub callRsync { 
    my ($actioned, $actioning, $restore) = @_;
    $options{'_backup-dir_'} or die "must specify backup target directory using instruction 'backupDir <directory>'\n";
    -e $options{'_backup-dir_'} and !(-d $options{'_backup-dir_'}) and die "$options{'_backup-dir_'} already exists but is not a directory\n";
    -d $options{'_backup-dir_'} or qx|mdkir -p $options{'_backup-dir_'}|;
    if($options{'dry-run'}){
        $options{'quiet'} or print "the following source directories will be $actioned\n";
    } else {
        $restore and (getPermission("files may be over-written during restore") or exit);  # only restore needs permission
        print "$actioning source directories\n";
    }
    foreach my $directory(sort {$a cmp $b} keys %backupDirs){
        $options{'quiet'} or print "  $directory\n";
        $directory =~ m|^/.+| or die "directories must be provided as absolute, not relative, paths\n";
        -e $directory and !(-d $directory) and die "$directory already exists but is not a directory\n";
        unless($options{'dry-run'}){
            -d $directory or qx|mdkir -p $directory|;
            my $rsync = $restore ?
                        "rsync -a $options{'_backup-dir_'}$directory/ $directory" :
                        "rsync -aR $directory $options{'_backup-dir_'}";
            my $output = qx|$rsync|; 
            $options{'quiet'} or print $output;
        }
    }
}
#========================================================================

1;

