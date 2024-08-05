<#
.SYNOPSIS
    Automates the installation and configuration of SQL Server, including additional setup tasks and optional SSMS installation.

.DESCRIPTION
    This script streamlines the installation and configuration of SQL Server. It mounts the SQL Server ISO, configures instance settings, applies necessary updates, and executes SQL scripts in a specified order. The script adheres to best practices, such as checking volume block sizes and optimizing SQL Server configurations for performance.

    Key Features:
    - Mounts the SQL Server ISO and retrieves the setup executable.
    - Installs SQL Server with specified configurations.
    - Configures TempDB settings, error log settings, and other SQL Server parameters.
    - Executes a series of SQL scripts in a specified order.
    - Checks for and optionally installs SQL Server Management Studio (SSMS).
    - Ensures SQL Server Agent is running and applies any necessary updates.
    - Utilizes relative paths for flexibility in script and directory locations.
    - Provides secure prompts for sensitive information, such as passwords.

    The script assumes a consistent directory structure, with all necessary files organized within the `sqlsetup` folder. It dynamically adapts to the root location of this folder, allowing for flexible deployment.

    Supported SQL Server Versions:
    - 2016
    - 2017
    - 2019
    - 2022

    Supported Editions:
    - Developer (for test and development)
    - Standard
    - Enterprise

    This script is open-source and licensed under the MIT License.

.PARAMETER sqlInstallerLocalPath
    Path to the SQL Server ISO file.

.PARAMETER ssmsInstallerPath
    Path to the SQL Server Management Studio installer.

.PARAMETER Version
    The version of SQL Server to install (e.g., 2016, 2017, 2019, 2022).

.PARAMETER edition
    The edition of SQL Server to install (e.g., Developer, Standard, Enterprise).

.PARAMETER productKey
    The product key for SQL Server installation. Required for Standard and Enterprise editions.

.PARAMETER collation
    The collation settings for SQL Server.

.PARAMETER SqlSvcAccount
    The service account for SQL Server.

.PARAMETER AgtSvcAccount
    The service account for SQL Server Agent.

.PARAMETER AdminAccount
    The administrator account for SQL Server.

.PARAMETER SqlDataDir
    The directory for SQL Server data files.

.PARAMETER SqlLogDir
    The directory for SQL Server log files.

.PARAMETER SqlBackupDir
    The directory for SQL Server backup files.

.PARAMETER SqlTempDbDir
    The directory for SQL Server TempDB files.

.PARAMETER TempdbDataFileSize
    The size of the TempDB data file in MB.

.PARAMETER TempdbDataFileGrowth
    The growth size of the TempDB data file in MB.

.PARAMETER TempdbLogFileSize
    The size of the TempDB log file in MB.

.PARAMETER TempdbLogFileGrowth
    The growth size of the TempDB log file in MB.

.PARAMETER Port
    The port for SQL Server.

.PARAMETER installSsms
    Indicates whether to install SQL Server Management Studio.

.PARAMETER debugMode
    Enables debug mode for detailed logging.

.EXAMPLE


.NOTES
    Author: Michael Pettersson, Cegal
    Version: 1.0
    License: MIT License
#>

# Get the current script directory
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# User Configurable Parameters
[string]$sqlInstallerLocalPath = "$scriptDir\SQLServer2022-x64-ENU-Dev.iso"
[string]$ssmsInstallerPath = "$scriptDir\SSMS-Setup-ENU.exe"
[ValidateSet(2016, 2017, 2019, 2022)]
[int]$Version = 2022
[ValidateSet("Developer", "Standard", "Enterprise")]
[string]$edition = "Developer"
[string]$productKey = $null
[string]$collation = "Finnish_Swedish_CI_AS"
[string]$SqlSvcAccount = "agdemo\sqlengine"
[string]$AgtSvcAccount = "agdemo\sqlagent"
[string]$AdminAccount = "agdemo\sqlgroup"
[string]$SqlDataDir = "E:\MSSQL\Data"
[string]$SqlLogDir = "F:\MSSQL\Log"
[string]$SqlBackupDir = "H:\MSSQL\Backup"
[string]$SqlTempDbDir = "G:\MSSQL\Data"
[string]$SqlTempDbLog = $SqlLogDir #"F:\MSSQL\Log"
[ValidateRange(512, [int]::MaxValue)]
[int]$TempdbDataFileSize = 512
[int]$TempdbDataFileGrowth = 64
[ValidateRange(64, [int]::MaxValue)]
[int]$TempdbLogFileSize = 64
[int]$TempdbLogFileGrowth = 64
[int]$Port = 1433
[bool]$installSsms = $false
[bool]$debugMode = $false

# Static parameters
[string]$server = $env:COMPUTERNAME
[string]$tableName = "CommandLog"

# Functions

# Function to log messages to a central log
function Log-Message {
    param (
        [string]$message,
        [string]$type = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$type] $message"
    Write-Host $logEntry

    if ($debugMode) {
        Write-Debug $logEntry
    }
}

# Function to show progress messages
function Show-ProgressMessage {
    param (
        [string]$activity,
        [string]$status,
        [int]$percentComplete
    )
    $progressParams = @{
        Activity        = $activity
        Status          = $status
        PercentComplete = $percentComplete
    }
    Write-Progress @progressParams
    Log-Message -message "$activity - $status ($percentComplete`%)"
}

# Function to validate volume paths and block sizes
function Test-Volume {
    param (
        [string[]]$paths
    )
    
    $drivesToCheck = $paths | ForEach-Object { $_[0] + ':' } | Sort-Object -Unique

    foreach ($drive in $drivesToCheck) {
        if (-not (Test-Path -Path $drive)) {
            Log-Message -message "Volume does not exist: $drive" -type "Error"
            throw "Volume does not exist: $drive"
        }

        $blockSize = Get-WmiObject -Query "SELECT BlockSize FROM Win32_Volume WHERE DriveLetter = '$drive'" | Select-Object -ExpandProperty BlockSize
        if ($blockSize -ne 65536) {
            Log-Message -message "Volume $drive does not use a 64 KB block size." -type "Error"
            throw "Volume $drive does not use a 64 KB block size."
        }
        else {
            Log-Message -message "Volume $drive uses a 64 KB block size." -type "Info"
        }
    }
}

# Function to prompt for secure passwords
function Get-SecurePasswords {
    $global:saPassword = Read-Host -AsSecureString -Prompt "Enter the SA password"
    $global:sqlServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server service account"
    $global:sqlAgentServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server Agent service account"
}

# Function to create PSCredential objects
function New-SqlCredentials {
    $global:saCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sa", $saPassword
    $global:sqlServiceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $SqlSvcAccount, $sqlServiceAccountPassword
    $global:sqlAgentCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $AgtSvcAccount, $sqlAgentServiceAccountPassword
}

# Function to mount ISO and get setup.exe path
function Mount-IsoAndGetSetupPath {
    param (
        [string]$isoPath
    )

    if (-Not (Test-Path -Path $isoPath)) {
        Log-Message -message "ISO file not found at path: $isoPath" -type "Error"
        throw "ISO file not found"
    }

    try {
        $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        $setupPath = "$($driveLetter):\setup.exe"
        Log-Message -message "Mounted ISO at $driveLetter and found setup.exe at $setupPath" -type "Info"
        return $setupPath, $driveLetter
    }
    catch {
        Log-Message -message "Failed to mount ISO and get setup.exe path. Error details: $_" -type "Error"
        throw
    }
}

# Function to unmount ISO
function Dismount-Iso {
    param (
        [string]$isoPath
    )

    try {
        $diskImage = Get-DiskImage -ImagePath $isoPath
        Dismount-DiskImage -ImagePath $diskImage.ImagePath
        Log-Message -message "Unmounted ISO at $($diskImage.DevicePath)" -type "Info"
    }
    catch {
        Log-Message -message "Failed to unmount ISO. Error details: $_" -type "Error"
        throw
    }
}

# Function to determine installer path
function Get-InstallerPath {
    param (
        [string]$installerPath
    )

    $fileExtension = [System.IO.Path]::GetExtension($installerPath).ToLower()
    Log-Message -message "Installer file extension: $fileExtension" -type "Info"

    if ($fileExtension -eq ".iso") {
        return Mount-IsoAndGetSetupPath -isoPath $installerPath
    }
    else {
        Log-Message -message "Unsupported file type: $fileExtension. Please provide a path to an .iso file." -type "Error"
        throw "Unsupported file type"
    }
}

# Function to get SQL Server version from the installer
function Get-SqlVersion {
    param (
        [string]$installerPath
    )

    if (Test-Path -Path $installerPath) {
        $versionInfo = (Get-Item $installerPath).VersionInfo
        return $versionInfo.ProductVersion
    }
    else {
        Log-Message -message "Installer not found at $installerPath" -type "Error"
        throw "Installer not found"
    }
}

# Function to map SQL Server version to year-based directory
function Get-UpdateDirectory {
    param (
        [string]$version
    )

    switch ($version.Split('.')[0]) {
        '13' { return "2016" }
        '14' { return "2017" }
        '15' { return "2019" }
        '16' { return "2022" }
        default { 
            Log-Message -message "Unsupported SQL Server version: $version" -type "Error"
            throw "Unsupported SQL Server version" 
        }
    }
}

# Function to check for reboot requirement
function Test-RebootRequirement {
    param (
        [string]$warnings
    )

    if ($warnings -like "*reboot*") {
        Log-Message -message "SQL Server installation requires a reboot." -type "Warning"
        
        try {
            $userInput = Read-Host "SQL Server installation requires a reboot. Do you want to reboot now? (Y/N)"
            if ($userInput -eq 'Y') {
                Restart-Computer -Force
            }
            else {
                Log-Message -message "Please reboot the computer manually to complete the installation." -type "Warning"
                throw "Reboot required"
            }
        }
        catch {
            Log-Message -message "An error occurred while attempting to prompt for a reboot. Error details: $_" -type "Error"
            throw
        }
    }
}

# Function to check if SSMS is installed
function Test-SsmsInstalled {
    param (
        [string]$ssmsVersion = "18"
    )

    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    
    foreach ($registryPath in $registryPaths) {
        $installedPrograms = Get-ChildItem -Path $registryPath -ErrorAction SilentlyContinue |
        Get-ItemProperty -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like "Microsoft SQL Server Management Studio*" }
        
        if ($installedPrograms) {
            Log-Message -message "SSMS is installed:" -type "Info"
            foreach ($program in $installedPrograms) {
                Log-Message -message "Name: $($program.DisplayName)" -type "Info"
                Log-Message -message "Version: $($program.DisplayVersion)" -type "Info"
            }
            return $true
        }
    }
    
    Log-Message -message "SSMS is not installed." -type "Warning"
    return $false
}

# Function to install SQL Server Management Studio (SSMS)
function Install-Ssms {
    param (
        [string]$installerPath
    )

    $params = "/Install /Quiet"

    try {
        Start-Process -FilePath $installerPath -ArgumentList $params -Wait
        Log-Message -message "SSMS installation completed." -type "Info"
    }
    catch {
        Log-Message -message "SSMS installation failed. Error details: $_" -type "Error"
        throw
    }
}

# Function to verify if updates were applied
function Test-UpdatesApplied {
    param (
        [string]$updateSourcePath
    )

    $updateFiles = Get-ChildItem -Path $updateSourcePath -Filter *.exe
    if ($updateFiles.Count -eq 0) {
        Log-Message -message "No update files found in ${updateSourcePath}" -type "Warning"
    }
    else {
        Log-Message -message "Update files found in ${updateSourcePath}:" -type "Info"
        foreach ($file in $updateFiles) {
            Log-Message -message "Update: $($file.Name)" -type "Info"
        }
    }
}

# Function to verify SQL script execution
function Test-SqlExecution {
    param (
        [string]$serverInstance,
        [string]$databaseName,
        [string]$query
    )

    try {
        Log-Message -message "Executing query on server: $serverInstance, database: $databaseName" -type "Info"
        Log-Message -message "Query: $query" -type "Info"

        $result = Invoke-DbaQuery -SqlInstance $serverInstance -Database $databaseName -Query $query -ErrorAction Stop

        if ($null -eq $result -or $result.Count -eq 0) {
            Log-Message -message "No data returned from the query or query returned a null result." -type "Error"
            throw "Query returned null or no data"
        }

        Log-Message -message "Query result: $($result | Format-Table -AutoSize | Out-String)" -type "Info"

        $tableExistsMessage = $result | Select-Object -ExpandProperty Column1
        Log-Message -message "Extracted Message: '$tableExistsMessage'" -type "Info"

        if ([string]::IsNullOrWhiteSpace($tableExistsMessage)) {
            Log-Message -message "Extracted Message is null or whitespace." -type "Error"
            throw "Query result message is null or whitespace"
        }

        if ($tableExistsMessage.Trim() -eq 'Table exists') {
            Log-Message -message "Verification successful: The table exists." -type "Info"
        }
        else {
            Log-Message -message "Verification failed: The table does not exist." -type "Error"
            throw "Table does not exist"
        }
    }
    catch {
        Log-Message -message "An error occurred during the verification query execution. Error details: $_" -type "Error"
        throw
    }
}

# Function to start SQL Server Agent
function Start-SqlServerAgent {
    param (
        [bool]$DebugMode
    )

    $agentServiceStatus = Get-Service -Name "SQLSERVERAGENT" -ErrorAction SilentlyContinue
    if ($agentServiceStatus -and $agentServiceStatus.Status -ne 'Running') {
        Log-Message -message "SQL Server Agent is not running. Attempting to start it..." -type "Warning"
        try {
            Start-Service -Name "SQLSERVERAGENT"
            Log-Message -message "SQL Server Agent started successfully." -type "Info"
        }
        catch {
            Log-Message -message "Failed to start SQL Server Agent. Error details: $_" -type "Error"
            throw
        }
    }
    else {
        Log-Message -message "SQL Server Agent is already running." -type "Info"
    }
}

# Function to initialize the dbatools module
function Initialize-DbatoolsModule {
    Log-Message -message "Checking if module dbatools is already loaded..." -type "Info"

    if (Get-Module -Name dbatools -ListAvailable) {
        Log-Message -message "Module dbatools is already loaded." -type "Info"
    }
    else {
        Log-Message -message "Loading module: dbatools..." -type "Info"
        try {
            Import-Module dbatools -ErrorAction Stop
            Log-Message -message "Module dbatools loaded successfully." -type "Info"
        }
        catch {
            Log-Message -message "Error: Failed to load module dbatools. Error details: $_" -type "Error"
            throw
        }
    }
}

# Function to read passwords and store them securely
function Read-Passwords {
    Show-ProgressMessage -activity "Preparation" -status "Prompting for input of passwords" -percentComplete 0
    try {
        Get-SecurePasswords
        New-SqlCredentials
        Show-ProgressMessage -activity "Preparation" -status "Passwords input completed" -percentComplete 100
    }
    catch {
        Log-Message -message "Failed to prompt for input of passwords. Error details: $_" -type "Error"
        throw
    }
}

# Function to set variables and verification query
function Set-Variables {
    param (
        [string]$scriptDir,
        [string]$tableName
    )

    [string]$scriptDirectory = "$scriptDir\Sql"
    [string]$orderFile = "$scriptDir\order.txt"

    [string]$verificationQuery = @"
IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$tableName')
BEGIN
    SELECT 'Table exists' AS Column1
END
ELSE
BEGIN
    SELECT 'Table does not exist' AS Column1
END
"@

    return @{
        scriptDirectory   = $scriptDirectory
        orderFile         = $orderFile
        verificationQuery = $verificationQuery
    }
}

# Function to restart SQL Server services
function Restart-SqlServices {
    param (
        [string]$server,
        [bool]$debugMode
    )

    Show-ProgressMessage -activity "Finalizing" -status "Restarting SQL Server services" -percentComplete 0
    try {
        Restart-DbaService -SqlInstance $server -Type Engine, Agent -Confirm:$false
        Log-Message -message "SQL Server services restarted successfully." -type "Info"
        Show-ProgressMessage -activity "Finalizing" -status "SQL Server services restarted" -percentComplete 100
    }
    catch {
        Log-Message -message "Failed to restart SQL Server services. Error details: $_" -type "Error"
        throw
    }
}

# Function to determine installer path, SQL version, and update directory
function Get-SqlInstallerDetails {
    param (
        [string]$installerPath,
        [string]$scriptDir
    )

    try {
        $installerDetails = Get-InstallerPath -installerPath $installerPath
        $setupPath = $installerDetails[0]
        $driveLetter = $installerDetails[1]

        if (-Not (Test-Path -Path $setupPath)) {
            Log-Message -message "Installer path not found: $setupPath" -type "Error"
            throw "Installer path not found"
        }

        $sqlVersion = Get-SqlVersion -installerPath $setupPath
        $updateDirectory = Get-UpdateDirectory -version $sqlVersion
        $updateSourcePath = "$scriptDir\Updates\$updateDirectory"

        return @{ 
            SetupPath        = $setupPath 
            DriveLetter      = $driveLetter 
            SqlVersion       = $sqlVersion 
            UpdateSourcePath = $updateSourcePath 
        }
    }
    catch {
        Log-Message -message "Failed to determine installer details. Error details: $_" -type "Error"
        throw
    }
}

# Function to unmount ISO if it was used
function Dismount-IfIso {
    param (
        [string]$installerPath
    )

    if ([System.IO.Path]::GetExtension($installerPath).ToLower() -eq ".iso") {
        Dismount-Iso -isoPath $installerPath
    }
}

# Function to invoke SQL scripts from an order file
function Invoke-SqlScriptsFromOrderFile {
    param (
        [string]$orderFile,
        [string]$scriptDirectory,
        [string]$server,
        [bool]$debugMode
    )

    $orderList = Get-Content -Path $orderFile

    foreach ($entry in $orderList) {
        $parts = $entry -split ":"
        $databaseName = $parts[0]
        $fileName = $parts[1]
        $filePath = Join-Path -Path $scriptDirectory -ChildPath $fileName

        if (Test-Path $filePath) {
            $scriptContent = Get-Content -Path $filePath -Raw

            try {
                Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $scriptContent
                Log-Message -message "Successfully executed script: $fileName on database: $databaseName" -type "Info"
            }
            catch {
                Log-Message -message "Failed to execute script: $fileName on database: $databaseName. Error details: $_" -type "Error"
                throw
            }
        }
        else {
            Log-Message -message "File not found: $fileName" -type "Error"
            throw "SQL script file not found"
        }
    }
}

# Function to invoke SQL Server installation
function Invoke-SqlServerInstallation {
    param (
        [string]$installerPath,
        [string]$updateSourcePath,
        [string]$driveLetter,
        [string]$server,
        [bool]$debugMode
    )
    
    $installParamsExtended = @{
        SqlTempdbFileCount    = 1
        SqlTempdbDir          = $SqlTempDbDir
        SqlTempdbLogDir       = $SqlTempDbLog
        BrowserSvcStartupType = "Disabled"
    }

    $installParams = @{
        SqlInstance                   = $server
        Version                       = $Version
        Verbose                       = $false
        Confirm                       = $false
        Feature                       = "Engine"
        InstancePath                  = "C:\Program Files\Microsoft SQL Server"
        DataPath                      = $SqlDataDir
        LogPath                       = $SqlLogDir
        BackupPath                    = $SqlBackupDir
        Path                          = "${driveLetter}:\"
        InstanceName                  = "MSSQLSERVER"
        AgentCredential               = $sqlAgentCredential
        AdminAccount                  = $AdminAccount
        UpdateSourcePath              = $updateSourcePath
        PerformVolumeMaintenanceTasks = $true
        AuthenticationMode            = "Mixed"
        EngineCredential              = $sqlServiceCredential
        Port                          = $Port
        SaCredential                  = $saCredential
        SqlCollation                  = $collation
        Configuration                 = $installParamsExtended
    }

    if ($edition -ne "Developer") {
        if ($null -eq $productKey) {
            Log-Message -message "Product key is required for Standard and Enterprise editions." -type "Error"
            throw "Product key required for selected edition"
        }
        $installParams.Pid = $productKey
    }

    if ($debugMode) {
        $VerbosePreference = "Continue"
    }
    else {
        $VerbosePreference = "SilentlyContinue"
    }

    Show-ProgressMessage -activity "Installation" -status "Starting SQL Server installation" -percentComplete 0
    try {
        Invoke-Command {
            Install-DbaInstance @installParams
        } -OutVariable installOutput -ErrorVariable installError -WarningVariable installWarning -Verbose:$false
        Show-ProgressMessage -activity "Installation" -status "SQL Server installation completed" -percentComplete 100
    }
    catch {
        Log-Message -message "SQL Server installation failed with an error. Exiting script. Error details: $_" -type "Error"
        throw
    }

    if ($debugMode) {
        Log-Message -message "Installation Output: $installOutput" -type "Info"
        Log-Message -message "Installation Errors: $installError" -type "Info"
        Log-Message -message "Installation Warnings: $installWarning" -type "Info"
    }

    Test-RebootRequirement -warnings $installWarning
}

# Function to set SQL Server settings
function Set-SqlServerSettings {
    param (
        [string]$server,
        [bool]$debugMode
    )

    Show-ProgressMessage -activity "Configuration" -status "Starting additional configuration steps" -percentComplete 0

    Test-Volume -paths @($SqlTempDbDir, $SqlTempDbLog, $SqlLogDir, $SqlDataDir, $SqlBackupDir)

    Show-ProgressMessage -activity "Configuration" -status "Configuring backup compression, optimize for ad hoc workloads, and remote admin connections" -percentComplete 20
    Get-DbaSpConfigure -SqlInstance $server -Name 'backup compression default', 'optimize for ad hoc workloads', 'remote admin connections' |
    ForEach-Object {
        Set-DbaSpConfigure -SqlInstance $server -Name $_.Name -Value 1
    }

    Show-ProgressMessage -activity "Configuration" -status "Setting cost threshold for parallelism" -percentComplete 30
    Set-DbaSpConfigure -SqlInstance $server -Name 'cost threshold for parallelism' -Value 75

    Show-ProgressMessage -activity "Configuration" -status "Setting recovery interval (min)" -percentComplete 40
    Set-DbaSpConfigure -SqlInstance $server -Name 'recovery interval (min)' -Value 60

    Show-ProgressMessage -activity "Configuration" -status "Configuring startup parameter for TraceFlag 3226" -percentComplete 50
    Set-DbaStartupParameter -SqlInstance $server -TraceFlag 3226 -Confirm:$false

    Show-ProgressMessage -activity "Configuration" -status "Setting max memory" -percentComplete 60
    Set-DbaMaxMemory -SqlInstance $server

    Show-ProgressMessage -activity "Configuration" -status "Setting max degree of parallelism" -percentComplete 70
    Set-DbaMaxDop -SqlInstance $server

    Show-ProgressMessage -activity "Configuration" -status "Configuring power plan" -percentComplete 80
    Set-DbaPowerPlan -ComputerName $server

    Show-ProgressMessage -activity "Configuration" -status "Configuring error log settings" -percentComplete 90
    Set-DbaErrorLogConfig -SqlInstance $server -LogCount 60 -LogSize 500

    Show-ProgressMessage -activity "Configuration" -status "Configuring database file growth settings for 'master' database" -percentComplete 91
    Set-DbaDbFileGrowth -SqlInstance $server -Database master -FileType Data -GrowthType MB -Growth 128
    Set-DbaDbFileGrowth -SqlInstance $server -Database master -FileType Log -GrowthType MB -Growth 64

    Show-ProgressMessage -activity "Configuration" -status "Configuring database file growth settings for 'msdb' database" -percentComplete 92
    Set-DbaDbFileGrowth -SqlInstance $server -Database msdb -FileType Data -GrowthType MB -Growth 128
    Set-DbaDbFileGrowth -SqlInstance $server -Database msdb -FileType Log -GrowthType MB -Growth 64

    Show-ProgressMessage -activity "Configuration" -status "Configuring database file growth settings for 'model' database" -percentComplete 93
    Set-DbaDbFileGrowth -SqlInstance $server -Database model -FileType Data -GrowthType MB -Growth 128
    Set-DbaDbFileGrowth -SqlInstance $server -Database model -FileType Log -GrowthType MB -Growth 64

    Show-ProgressMessage -activity "Configuration" -status "Configuring SQL Agent server settings" -percentComplete 94
    try {
        Set-DbaAgentServer -SqlInstance $server -MaximumJobHistoryRows 0 -MaximumHistoryRows -1 -ReplaceAlertTokens Enabled
    }
    catch {
        Log-Message -message "Warning: Failed to configure SQL Agent server settings. Ensure 'Agent XPs' is enabled. Error details: $_" -type "Warning"
    }
    
    $cpuCores = (Get-WmiObject -Class Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $maxCores = if ($cpuCores -gt 8) { 8 } else { $cpuCores }

    Show-ProgressMessage -activity "Configuration" -status "Configuring TempDB" -percentComplete 95
    try {
        Set-DbaTempDbConfig -SqlInstance $server -DataFileCount $maxCores -DataFileSize $TempdbDataFileSize -LogFileSize $TempdbLogFileSize -DataFileGrowth $TempdbDataFileGrowth -LogFileGrowth $TempdbLogFileGrowth -ErrorAction Stop
    }
    catch {
        Log-Message -message "Warning: Failed to configure TempDB. Error details: $_" -type "Warning"
    }

    Show-ProgressMessage -activity "Configuration" -status "Additional configuration steps completed" -percentComplete 100
}

# Function to install SQL Server Management Studio if requested
function Install-SSMSIfRequested {
    param (
        [bool]$installSsms,
        [string]$ssmsInstallerPath,
        [bool]$debugMode
    )

    if ($installSsms) {
        if (Test-SsmsInstalled) {
            Log-Message -message "SQL Server Management Studio (SSMS) is already installed. Exiting script." -type "Error"
            throw "SSMS already installed"
        }

        Show-ProgressMessage -activity "Installation" -status "Installing SQL Server Management Studio (SSMS)" -percentComplete 0
        Install-Ssms -installerPath $ssmsInstallerPath
        Show-ProgressMessage -activity "Installation" -status "SQL Server Management Studio (SSMS) installed" -percentComplete 100
    }
    else {
        Log-Message -message "SSMS installation not requested. Skipping SSMS installation." -type "Warning"
    }
}

# Function to show final informational message
function Show-FinalMessage {
    Log-Message -message "SQL Server installation and configuration completed successfully." -type "Info"
    if ($debugMode) { 
        Log-Message -message "SQL Server installation and configuration completed successfully on server $server" -type "Info"
    }

    $sqlVersionDirectory = switch ($Version) {
        2016 { "130" }
        2017 { "140" }
        2019 { "150" }
        2022 { "160" }
        default { 
            Log-Message -message "Unsupported SQL Server version: $Version" -type "Error"
            throw "Unsupported SQL Server version" 
        }
    }

    Log-Message -message "" -type "Info"
    Log-Message -message "Installation Complete! Here is some additional information:" -type "Info"
    Log-Message -message "----------------------------------------------------------------------------------------" -type "Info"
    Log-Message -message "- Log Files: Check the installation log located at:" -type "Info"
    Log-Message -message "  C:\Program Files\Microsoft SQL Server\$sqlVersionDirectory\Setup Bootstrap\Log\Summary.txt" -type "Info"
    Log-Message -message "- Setup Monitoring: Visit the following URL to find a script for manual setup." -type "Info"
    Log-Message -message "  https://github.com/sqlsweden/sqlZetup/blob/main/Monitoring/zetupMonitoring.sql" -type "Info"
    Log-Message -message "- Include the backup volume in the backup for the file level backup." -type "Info"
    Log-Message -message "- Exclude the database files and folders from the antivirus software if it's used." -type "Info"
    Log-Message -message "- Document the passwords used in this installation at the proper location." -type "Info"
    Log-Message -message "" -type "Info"
    Log-Message -message "- The current sql server agent jobs are scheduled like this. It might be necessary to adjust." -type "Info"
   
    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | Job Type                                                | Frequency       | Time    |" -type "Info"
    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | User databases                                          |                 |         |" -type "Info"
    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | DBA - Database Backup - USER_DATABASES - FULL           | Sunday          | 21:15   |" -type "Info"
    Log-Message -message " | DBA - Database Backup - USER_DATABASES - DIFF           | daily (ex. Sun) | 21:15   |" -type "Info"
    Log-Message -message " | DBA - Database Backup - USER_DATABASES - LOG            | Daily           | 15m int |" -type "Info"
    Log-Message -message " | DBA - Database Integrity Check - USER_DATABASES         | Saturday        | 23:45   |" -type "Info"
    Log-Message -message " | DBA - Index Optimize - USER_DATABASES                   | Friday          | 18:00   |" -type "Info"
    Log-Message -message " | DBA - Statistics Update - USER_DATABASES                | Daily           | 03:00   |" -type "Info"

    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | System databases                                        |                 |         |" -type "Info"
    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | DBA - Database Backup - SYSTEM_DATABASES - FULL         | Daily           | 21:05   |" -type "Info"
    Log-Message -message " | DBA - Database Integrity Check - SYSTEM_DATABASES       | Sunday          | 20:45   |" -type "Info"
    Log-Message -message " | DBA - Index And Statistics Optimize - SYSTEM_DATABASES  | Sunday          | 20:15   |" -type "Info"

    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | Cleanup                                                 |                 |         |" -type "Info"
    Log-Message -message " |---------------------------------------------------------|-----------------|---------|" -type "Info"
    Log-Message -message " | DBA - Delete Backup History                             | Sunday          | 02:05   |" -type "Info"
    Log-Message -message " | DBA - Purge Job History                                 | Sunday          | 02:05   |" -type "Info"
    Log-Message -message " | DBA - Command Log Cleanup                               | Sunday          | 02:05   |" -type "Info"
    Log-Message -message " | DBA - Output File Cleanup                               | Sunday          | 02:05   |" -type "Info"
    Log-Message -message " | DBA - Purge Mail Items                                  | Sunday          | 02:05   |" -type "Info"
    Log-Message -message " ---------------------------------------------------------------------------------------" -type "Info"
    Log-Message -message "" -type "Info"
}

# Function to validate collation
function Test-Collation {
    param (
        [string]$collation,
        [string]$scriptDir
    )

    $collationFilePath = Join-Path -Path $scriptDir -ChildPath "collation.txt"

    if (-Not (Test-Path -Path $collationFilePath)) {
        Log-Message -message "Collation file not found at path: $collationFilePath" -type "Error"
        throw "Collation file not found"
    }

    $validCollations = Get-Content -Path $collationFilePath

    if ($collation -notin $validCollations) {
        Log-Message -message "Invalid collation: $collation. Please specify a valid collation." -type "Error"
        throw "Invalid collation specified"
    }
}

# Main Function to install and configure SQL Server
function Invoke-InstallSqlServer {
    try {
        Show-ProgressMessage -activity "Validation" -status "Validating collation" -percentComplete 0
        Test-Collation -collation $collation -scriptDir $scriptDir
        Show-ProgressMessage -activity "Validation" -status "Collation validated" -percentComplete 100

        Show-ProgressMessage -activity "Initialization" -status "Initializing dbatools module" -percentComplete 0
        Initialize-DbatoolsModule
        Show-ProgressMessage -activity "Initialization" -status "dbatools module initialized" -percentComplete 100

        Show-ProgressMessage -activity "Validation" -status "Verifying volume paths and block sizes" -percentComplete 0
        Test-Volume -paths @($SqlTempDbDir, $SqlTempDbLog, $SqlLogDir, $SqlDataDir, $SqlBackupDir)
        Show-ProgressMessage -activity "Validation" -status "Volume paths and block sizes verified" -percentComplete 100

        Read-Passwords

        Show-ProgressMessage -activity "Installation" -status "Determining installer path" -percentComplete 0
        $sqlInstallerDetails = Get-SqlInstallerDetails -installerPath $sqlInstallerLocalPath -scriptDir $scriptDir
        $setupPath = $sqlInstallerDetails.SetupPath
        $driveLetter = $sqlInstallerDetails.DriveLetter
        $updateSourcePath = $sqlInstallerDetails.UpdateSourcePath

        Invoke-SqlServerInstallation -installerPath $setupPath -updateSourcePath $updateSourcePath -driveLetter $driveLetter -server $server -debugMode $debugMode
        Dismount-IfIso -installerPath $sqlInstallerLocalPath

        Set-SqlServerSettings -server $server -debugMode $debugMode

        $variables = Set-Variables -scriptDir $scriptDir -tableName $tableName
        $scriptDirectory = $variables.scriptDirectory
        $orderFile = $variables.orderFile
        $verificationQuery = $variables.verificationQuery

        Invoke-SqlScriptsFromOrderFile -orderFile $orderFile -scriptDirectory $scriptDirectory -server $server -debugMode $debugMode

        Test-SqlExecution -serverInstance $server -databaseName "DBAdb" -query $verificationQuery

        Restart-SqlServices -server $server -debugMode $debugMode

        Install-SSMSIfRequested -installSsms $installSsms -ssmsInstallerPath $ssmsInstallerPath -debugMode $debugMode

        Show-FinalMessage
    }
    catch {
        Log-Message -message "An error occurred during the SQL Server installation process. Error details: $_" -type "Error"
        throw
    }
    finally {
        Log-Message -message "Script execution completed." -type "Info"
    }
}

# Start the installation process
Invoke-InstallSqlServer
