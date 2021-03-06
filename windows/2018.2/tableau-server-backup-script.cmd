:: THE INFORMATION LAB BACKUP SCRIPT
:: https://github.com/til-jmac/tableau-server-housekeeping
:: Authored by Jonathan MacDonald
:: Last updated 27/08/2018
:: How to use this script
:: 1) Create a scripts directory somewhere that makes sense for this (and other) scripts to be kept. Inside your Tableau Server 'data' folder is a good place. 
:: 2) The command line parameters are ALL required. Ensure you use them in the correct order or the script will fail
:: 3) Run this script as a user with permissions to authenticate to TSM. Also run it with elevated (administrator) privileges.
:: 4) I would recommend you backup daily. 
:: 5) Use this script in conjunction with my log archival and cleanup scripts, which you can find at the Github link above
:: Give me a shout on Twitter @macdonaldj for questions, comments or feedback

@echo OFF
cls

:: Checks that the script is being run with Admin rights. 
:check_admin
NET SESSION >NUL 2>&1
if %ERRORLEVEL% NEQ 0 (
  ECHO %date% %time% : This script must be run as Administrator. Cancelling.
  EXIT /B 1
)

:: Sets a global script variable for later
SET overwrite_requested=false

:: Let's grab a consistent date in the same format that Tableau Server writes the date to the end of the backup file name
:set_date
FOR /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') DO SET "dt=%%a"
SET "YY=%dt:~2,2%" & SET "YYYY=%dt:~0,4%" & SET "MM=%dt:~4,2%" & SET "DD=%dt:~6,2%"
SET "HH=%dt:~8,2%" & SET "Min=%dt:~10,2%" & SET "Sec=%dt:~12,2%"
SET "mydate=%YYYY%-%MM%-%DD%"

:: Parses command line parameters
:parse_command_line_params
IF "%1"=="" GOTO end_parse
IF "%1"=="-n" GOTO name_arg
IF "%1"=="--name" GOTO name_arg
IF "%1"=="-u" GOTO tsmadmin_arg
IF "%1"=="--username" GOTO tsmadmin_arg
IF "%1"=="-p" GOTO tsmpassword_arg
IF "%1"=="--password" GOTO tsmpassword_arg
IF "%1"=="-d" GOTO backupdays_arg
IF "%1"=="--days" GOTO backupdays_arg
IF "%1"=="-o" GOTO overwrite_requested_arg
IF "%1"=="--overwrite" GOTO overwrite_requested_arg
IF "%1"=="-h" GOTO show_help
IF "%1"=="--help" GOTO show_help

:name_arg
SHIFT
SET filename=%1
ECHO %date% %time% : Setting the filename to: "%filename%"
SHIFT
GOTO parse_command_line_params

:tsmadmin_arg
SHIFT
SET tsmadmin=%1
ECHO %date% %time% : Executing TSM as user: "%tsmadmin%"
SHIFT
GOTO parse_command_line_params

:tsmpassword_arg
SHIFT
SET tsmpassword=%1
ECHO %date% %time% : Using %tsmadmin% password: "***SECRET***"
SHIFT
GOTO parse_command_line_params

:backupdays_arg
SHIFT
SET backupdays=%1
ECHO %date% %time% : Setting the backup retention period to: "%backupdays%" days
SHIFT
GOTO parse_command_line_params

:overwrite_requested_arg
SHIFT
SET overwrite_requested=%1
ECHO %date% %time% : Setting overwrite request to: "%overwrite_requested%"
SHIFT
GOTO parse_command_line_params

:end_parse

:: Series of checks to ensure command line params are input and valid
:check_filename
IF "%filename%" == "" (
	ECHO ERROR: Please specify a valid filename. Cancelling.
	GOTO show_help
	)

:check_username
IF "%tsmadmin%" == "" (
	ECHO ERROR: Please specify a valid TSM user. Cancelling. 
	GOTO show_help
	)

:check_password
IF "%tsmpassword%" == "" (
	ECHO ERROR: Please specify a valid TSM password. Cancelling.
	GOTO show_help
	)

:check_retention_period
IF "%backupdays%" == "" (
	ECHO ERROR: Please specify a valid retention period. Cancelling.
	GOTO show_help
	)

:: The new TSM backup command will not overwrite a file of the same name
:: Given we are appending today's date to the end of the filename this should not be a problem if you are backing up daily
:: However, if you are backing up more frequently than that, for testing for example, you may want to overwrite the existing file 
:: Using the '-o' parameter with this script will overwrite the existing file
:: So let's check if this was used    
:check_overwrite
ECHO %date% %time% : Checking if overwrite was requested
IF NOT DEFINED overwrite_requested ( 
	ECHO ERROR: Please specify true/false for overwrite flag. Cancelling. 
	GOTO show_help
	)
IF NOT %overwrite_requested% == true GOTO no_overwrite
IF %overwrite_requested% == true GOTO overwrite 

:: It was used so let's delete the current file if it's there
:overwrite
ECHO %date% %time% : Overwrite was requested. Cleaning out any existing file with the same name
IF EXIST "%backuppath%\%filename%-%mydate%.tsbak" DEL /F "%backuppath%\%filename%-%mydate%.tsbak" >nul 2>&1
GOTO set_backup_dir

:: It wasn't used so let's just go ahead and backup
:no_overwrite
ECHO %date% %time% : Overwrite was not requested, proceeding

:: Let's find the locations of some directories using tsm 
:: ECHO Setting the script location variable
:: Grab the location of this script
:: SET script_dir=%~dp0

:: Grab the location of the backup directory
:set_backup_dir
ECHO %date% %time% : Getting the location of the default backup directory
FOR /F "tokens=* USEBACKQ" %%F IN (`tsm configuration get -k basefilepath.backuprestore -u %tsmadmin% -p %tsmpassword%`) DO (SET "backuppath=%%F")
ECHO The default backup path is: 
ECHO %backuppath%

:: In v2018.2.0 the slashes in the default path are the wrong direction, so let's fix this
:fix_backup_dir
SET "backuppath=%backuppath:/=\%"
ECHO The corrected backup path is now: 
ECHO %backuppath% 

:: ECHO Deriving the location of the install directory
:: Derive the location of the install directory 
:: FOR %%I IN ("%backuppath%\..\..\..\..") DO SET install_dir=%%~fI

:: Now let's actually do some stuff
:: Check for previous backups and remove backup files older than N days
:delete_old_files
ECHO %date% %time% : Cleaning out backup files older than %backupdays% days
FORFILES -p "%backuppath%" -s -m *.tsbak /D -%backupdays% /C "cmd /c del @path" 2>nul

:: Then we take the backup
:bakup
ECHO %date% %time% : Backing up Tableau Server data
CALL tsm maintenance backup -f "%filename%" -d -u %tsmadmin% -p %tsmpassword%

:: Then we backup the settings config file
:settings_bakup
CALL tsm settings export -f "%backuppath%\%filename%-settings.json" -u %tsmadmin% -p %tsmpassword% 
::%filename% -d -u %tsmadmin% -p %tsmpassword%

:end_msg
IF %ERRORLEVEL% EQU 0 (
	ECHO %date% %time% : Backup completed succesfully. 
	EXIT /B 0 
	)
IF %ERRORLEVEL% GTR 0 (
	ECHO %date% %time% : Backup failed with exit code %ERRORLEVEL%
	GOTO show_help
	) 

:show_help
ECHO Usage: 
ECHO tableau-server-backup-script.cmd -n ^<filename^> -u ^<username^> -p ^<password^> -d ^<days^> -o ^<true/false^>
ECHO Required parameters (use in sequence):
ECHO 		-n,--name 		Name of the backup file (no spaces, periods or funny characters)
ECHO 		-u,--username 		TSM administrator username
ECHO 		-p,--password 		TSM administrator password 
ECHO 		-d,--days 		Delete backup files in the backup location older than N days
ECHO 		-o,--overwrite 		Overwrite any existing backup with the same name (takes appended date into account)
ECHO 		-h,--help 		Show this help 
EXIT /B 3