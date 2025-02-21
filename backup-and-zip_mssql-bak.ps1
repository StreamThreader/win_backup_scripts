
# Version 1.03
# 
# By default (for ERP database)
# 1) Search all files like:
#  2025-02-20-ERP-11-10-00-full-d.bak
#  2025-02-20-ERP-11-10-00-diff-d.bak
#  2025-02-20-ERP-11-10-00-txlog-d.bak
#
# 2) Compress into 2025-02-20-ERP-d.7z
#
# 3) Move to remote smb share

# list of databases
$db_names = @(
    "ERP",
    "SKD"
)
# local uncompressed bak files
$backup_path = "E:\DBServer\SQL-BackUP\"
$backup_fs_path = ""
$log_file = $backup_path+"00-logfile.txt"
$backup_date = (Get-Date -Format "yyyy-MM-dd").ToString()
$robocopyexe = "C:\Windows\System32\Robocopy.exe"
$zipexe = "C:\Progra~1\7-Zip\7z.exe"
# compression level (default normal)
$ziplevel = "5"
# number of used CPU cores
$zipcpu = "12"
# expected compression ratio in %
$compress_ratio = 10
# tmp variables
$expect_zip_size = 0
$used_by_files = 0
$size = 0
$fqdn_bakfile = ""
$zipfile_name = ""
$fqdn_zipfile = ""
$diff_size = 0
$tmp_msg = ""

# check log file exist
If (!(test-path $log_file)) {
    If (!(New-Item -type file -force $log_file)) {
        exit 1
    }
}

# function for writing log
Function logwriter($log_code_status, $log_msg){
    $backup_date_time = (Get-Date `
        -Format "yyyy-MM-dd_HH:mm:ss").ToString()

    If ($log_code_status) {
        $log_status = "[FAILED]"
    } else {
        $log_status = "[OK]"
    }
    
    $log_msg = $backup_date_time+" - "+$log_status+" "+$log_msg
    
    $log_msg | Out-File -append $log_file
}

$tmp_msg = "--------------------- NEW SESSION ---------------"
logwriter 0 $tmp_msg

# check directory exist
If (!(test-path $backup_path)) {
    $tmp_msg = "directory: "+$backup_path+" not exist"
    logwriter 1 $tmp_msg
    exit 1
}

foreach ($db_name in $db_names) {
    $tmp_msg = "---------- start new task: "+$db_name+" --------"
    logwriter 0 $tmp_msg
    $zipfile_name = $backup_date+"-"+$db_name+"-d.7z"
    $fqdn_zipfile = $backup_path+$zipfile_name
    $tmp_msg = "zip file: "+$zipfile_name
    logwriter 0 $tmp_msg

    # remote storage path
    $backup_fs_path = "\\fs-02\BackUp\1C-"+$db_name+"\SQL\"
    $tmp_msg = "local target path: "+$backup_path
    logwriter 0 $tmp_msg
   
    $tmp_msg = "remote storage for backup: "+$backup_fs_path
    logwriter 0 $tmp_msg
    # check remote directory exist
    If (!(test-path $backup_fs_path)) {
        $tmp_msg = "remote directory: "+$backup_fs_path+" not exist"
        logwriter 1 $tmp_msg
        exit 1
    }

    # name of pattern local bak files
    $bak_files = $backup_date+"-"+$db_name+"-??-??-??-*-d.bak"
    $tmp_msg = "file name search pattern: "+$bak_files
    logwriter 0 $tmp_msg

    # 1) get list of files for each database by pattern
    $files = Get-ChildItem $backup_path -Name -Include $bak_files

    # get used space by bak files
    $used_by_files = 0
    foreach ($file_name in $files) {
        $fqdn_bakfile = $backup_path+$file_name
        $size = get-childitem $fqdn_bakfile | `
            Select-Object -ExpandProperty Length

        $used_by_files = ($used_by_files + $size)
    }
    $tmp_msg = "used space by uncompressed files: "+`
        $used_by_files+" bytes"
    logwriter 0 $tmp_msg

    # calculate expected archive size
    $expect_zip_size = ($used_by_files / 100) * $compress_ratio
    $tmp_msg = "expected zip size is: "+$expect_zip_size+" bytes"
    logwriter 0 $tmp_msg

    # get free space on disk
    $backup_path_space = (Get-Volume -FilePath $backup_path).SizeRemaining;
    $tmp_msg = "free space on "+$backup_path+": "+`
        $backup_path_space+" bytes"
    logwriter 0 $tmp_msg

    # compare free space and expected
    If ($backup_path_space -lt $expect_zip_size) {
        $tmp_msg = "no enough space"
        logwriter 1 $tmp_msg
        exit 1
    }

    # 2) add each file from list to zip archive
    foreach ($file_name in $files) {
        $file_name = $file_name.ToString()

        $tmp_msg = "compress started: "+$file_name
        logwriter 0 $tmp_msg

        $cmd_args = "a -y -mx="+$ziplevel+`
            " -mmt="+$zipcpu+" -sdel "+`
            $fqdn_zipfile+" "+`
            $backup_path+$file_name

        # Set low process priority
        $program = Start-Process $zipexe $cmd_args -PassThru
        $program.PriorityClass = "Idle"
        $program.WaitForExit()
        
        # check 7zip exit code
        if ($program.ExitCode) {
            $tmp_msg = "compressing failed: "+$file_name
            logwriter 1 $tmp_msg
        } else {
            $tmp_msg = "compressing finished: "+$file_name
            logwriter 0 $tmp_msg
        }
    }

    # test zip file after creation
    if (test-path $fqdn_zipfile) {
        $size = get-childitem $fqdn_zipfile | `
            Select-Object -ExpandProperty Length
        $tmp_msg = "real zip file size: "+$size+" bytes"
        logwriter 0 $tmp_msg

        $diff_size = $expect_zip_size - $size
        $tmp_msg = "final expectation size difference: "+`
            $diff_size+" bytes"
        logwriter 0 $tmp_msg
    } else {
        $tmp_msg = "zip file: "+$fqdn_zipfile+" not found"
        logwriter 1 $tmp_msg
        exit 1
    }

    # 3) move backups to remote storage
    If (test-path $backup_fs_path) {
        $cmd_args = "/MOV "+$backup_path+`
            " "+$backup_fs_path+`
            " "+$zipfile_name

        $tmp_msg = "start move: "+$zipfile_name
        logwriter 0 $tmp_msg

        # Set low process priority
        $program = Start-Process $robocopyexe $cmd_args -PassThru
        $program.PriorityClass = "Idle"
        $program.WaitForExit()

        # check robocopy exit code
        if ($program.ExitCode) {
            $tmp_msg = "move finished: "+$zipfile_name
            logwriter 0 $tmp_msg
        } else {
            $tmp_msg = "move failed: "+$zipfile_name
            logwriter 1 $tmp_msg
        }

        # check file after moving
        If (test-path $backup_fs_path$zipfile_name) {
            $tmp_msg = "file: "+$zipfile_name+`
                " exist on remote storage"
            logwriter 0 $tmp_msg
        } else {
            $tmp_msg = "file: "+$zipfile_name+`
                " not found on remote storage"
            logwriter 1 $tmp_msg
        }

        New-Item -type file -force $backup_fs_path"\ready.flag"
        $tmp_msg = "set ready flag on remote path"
        logwriter 0 $tmp_msg
    } else {
        $tmp_msg = "remote storage path "+$backup_fs_path+`
            " not exist"
        logwriter 1 $tmp_msg
    }
}
