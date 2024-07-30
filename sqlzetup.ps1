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

.AUTHOR
    Michael Pettersson

.VERSION
    1.0
#>

# Get the current script directory
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# User Configurable Parameters
[string]$sqlInstallerLocalPath = "$scriptDir\SQLServer2022-x64-ENU-Dev.iso"
[string]$ssmsInstallerPath = "$scriptDir\SSMS-Setup-ENU.exe"
[int]$Version = 2022
[string]$edition = "Developer"
[string]$productKey = $null
[string]$SqlDataDir = "E:\MSSQL\Data"
[string]$SqlLogDir = "F:\MSSQL\Log"
[string]$SqlBackupDir = "H:\MSSQL\Backup"
[string]$SqlCollation = "Finnish_Swedish_CI_AS"
[int]$Port = 1433
[string]$AdminAccount = "agdemo\sqlgroup"
[string]$SqlTempDbLogDir = $SqlLogDir
[string]$SqlTempDbDir = "G:\MSSQL\Data"
[ValidateSet("Automatic", "Disabled", "Manual")]
[string]$BrowserSvcStartupType = "Disabled"
[ValidateSet(0, 1)]
[int]$NpEnabled = 0
[ValidateSet(0, 1)]
[int]$TcpEnabled = 1
[ValidateRange(512, [int]::MaxValue)]
[int]$TempdbDataFileSize = 512 # MB
[ValidateRange(64, [int]::MaxValue)]
[int]$TempdbLogFileSize = 64
[int]$TempdbLogFileGrowth = 64
[bool]$installSsms = $false
[bool]$debugMode = $false
[int]$SqlTempDbFileCount = 1

$config = @{
    SqlSvcAccount         = "agdemo\sqlengine"
    AgtSvcAccount         = $null # Specifying $null = SqlSvcAccount # "agdemo\sqlagent"
    SqlTempDbLogDir       = $SqlTempDbLogDir
    SqlTempDbDir          = $SqlTempDbDir
    SqlTempDbFileCount    = $SqlTempDbFileCount # Ensure SqlTempDbFileCount is included
    BrowserSvcStartupType = $BrowserSvcStartupType
    NpEnabled             = $NpEnabled
    TcpEnabled            = $TcpEnabled
    SqlSvcPassword        = $null
    AgtSvcPassword        = $null
    SaPwd                 = $null
}

# Static parameters
[string]$server = $env:COMPUTERNAME
[string]$tableName = "CommandLog"

# Functions

# Function to show progress messages
function Show-ProgressMessage {
    param (
        [string]$message
    )
    Write-Host "$message"
    if ($debugMode) {
        Write-Debug "$message"
    }
}

# Function to verify if the volume block size is 64 KB
function Test-VolumeBlockSize {
    param (
        [string[]]$paths
    )
    
    $drivesToCheck = $paths | ForEach-Object { $_[0] + ':' } | Sort-Object -Unique

    $blockSizeOK = $true
    foreach ($drive in $drivesToCheck) {
        $blockSize = Get-WmiObject -Query "SELECT BlockSize FROM Win32_Volume WHERE DriveLetter = '$drive'" | Select-Object -ExpandProperty BlockSize
        if ($blockSize -ne 65536) {
            Write-Host "Volume $drive does not use a 64 KB block size." -ForegroundColor Red
            if ($debugMode) { Write-Debug "BlockSize for volume $drive is $blockSize instead of 65536." }
            $blockSizeOK = $false
        }
        else {
            Write-Host "Volume $drive uses a 64 KB block size." -ForegroundColor Green
        }
    }

    return $blockSizeOK
}

# Function to prompt for secure passwords
function Get-SecurePasswords {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "Get-SecurePasswords")]
    $global:saPassword = Read-Host -AsSecureString -Prompt "Enter the SA password"
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "Get-SecurePasswords")]
    $global:sqlServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server service account"

    # Only prompt for Agent password if different from SqlSvcAccount
    if ($config.SqlSvcAccount -ne $config.AgtSvcAccount) {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "Get-SecurePasswords")]
        $global:sqlAgentServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server Agent service account"
    }
    else {
        $global:sqlAgentServiceAccountPassword = $global:sqlServiceAccountPassword
    }
}

# Function to create PSCredential objects
function New-SqlCredentials {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "New-SqlCredentials")]
    $global:saCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sa", $saPassword
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "New-SqlCredentials")]
    $global:sqlServiceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $config.SqlSvcAccount, $sqlServiceAccountPassword
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "New-SqlCredentials")]
    $global:sqlAgentCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $config.AgtSvcAccount, $sqlAgentServiceAccountPassword
}

# Function to mount ISO and get setup.exe path
function Mount-IsoAndGetSetupPath {
    param (
        [string]$isoPath
    )

    if (-Not (Test-Path -Path $isoPath)) {
        Write-Host "ISO file not found at path: $isoPath" -ForegroundColor Red
        if ($debugMode) { Write-Debug "ISO file not found at path: $isoPath" }
        Exit 1
    }

    try {
        $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
        $driveLetter = ($mountResult | Get-Volume).DriveLetter
        $setupPath = "$($driveLetter):\setup.exe"
        if ($debugMode) { Write-Debug "Mounted ISO at $driveLetter and found setup.exe at $setupPath" }
        return $setupPath, $driveLetter
    }
    catch {
        Write-Host "Failed to mount ISO and get setup.exe path." -ForegroundColor Red
        Write-Host "Error details: $_"
        Exit 1
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
        if ($debugMode) { Write-Debug "Unmounted ISO at $($diskImage.DevicePath)" }
    }
    catch {
        Write-Host "Failed to unmount ISO." -ForegroundColor Red
        Write-Host "Error details: $_"
        Exit 1
    }
}

# Function to determine installer path
function Get-InstallerPath {
    param (
        [string]$installerPath
    )

    $fileExtension = [System.IO.Path]::GetExtension($installerPath).ToLower()

    if ($debugMode) { Write-Debug "Installer file extension: $fileExtension" }

    if ($fileExtension -eq ".iso") {
        return Mount-IsoAndGetSetupPath -isoPath $installerPath
    }
    else {
        Write-Host "Unsupported file type: $fileExtension. Please provide a path to an .iso file." -ForegroundColor Red
        if ($debugMode) { Write-Debug "Unsupported file type: $fileExtension" }
        Exit 1
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
        Write-Host "Installer not found at $installerPath" -ForegroundColor Red
        if ($debugMode) { Write-Debug "Installer not found at $installerPath" }
        Exit 1
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
            Write-Host "Unsupported SQL Server version: $version" -ForegroundColor Red
            if ($debugMode) { Write-Debug "Unsupported SQL Server version: $version" }
            throw "Unsupported SQL Server version: $version" 
        }
    }
}

# Function to check for reboot requirement
function Test-RebootRequirement {
    param (
        [string]$warnings
    )

    if ($warnings -like "*reboot*") {
        Write-Host "SQL Server installation requires a reboot." -ForegroundColor Red
        if ($debugMode) { Write-Debug "SQL Server installation requires a reboot." }
        
        try {
            $userInput = Read-Host "SQL Server installation requires a reboot. Do you want to reboot now? (Y/N)"
            if ($userInput -eq 'Y') {
                Restart-Computer -Force
            }
            else {
                Write-Host "Please reboot the computer manually to complete the installation." -ForegroundColor Yellow
                Exit 1
            }
        }
        catch {
            Write-Host "An error occurred while attempting to prompt for a reboot." -ForegroundColor Red
            if ($debugMode) { Write-Debug "Error details: $_" }
            Exit 1
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
            Write-Host "SSMS is installed:"
            if ($debugMode) { Write-Debug "SSMS installed programs found in registry path: $registryPath" }
            foreach ($program in $installedPrograms) {
                Write-Host "Name: $($program.DisplayName)"
                Write-Host "Version: $($program.DisplayVersion)"
            }
            return $true
        }
    }
    
    Write-Host "SSMS is not installed."
    if ($debugMode) { Write-Debug "SSMS is not installed in any of the checked registry paths." }
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
        Write-Host "SSMS installation completed." -ForegroundColor Green
        if ($debugMode) { Write-Debug "SSMS installation completed using installer path: $installerPath" }
    }
    catch {
        Write-Host "SSMS installation failed." -ForegroundColor Red
        Write-Host "Error details: $_"
        Exit 1
    }
}

# Function to verify if updates were applied
function Test-UpdatesApplied {
    param (
        [string]$updateSourcePath
    )

    $updateFiles = Get-ChildItem -Path $updateSourcePath -Filter *.exe
    if ($updateFiles.Count -eq 0) {
        Write-Host "No update files found in ${updateSourcePath}" -ForegroundColor Yellow
        if ($debugMode) { Write-Debug "No update files found in ${updateSourcePath}" }
    }
    else {
        Write-Host "Update files found in ${updateSourcePath}:"
        foreach ($file in $updateFiles) {
            Write-Host "Update: $($file.Name)"
            if ($debugMode) { Write-Debug "Update file found: $($file.Name)" }
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
        Write-Host "Executing query on server: $serverInstance, database: $databaseName" -ForegroundColor Yellow
        Write-Host "Query: $query" -ForegroundColor Yellow

        $result = Invoke-DbaQuery -SqlInstance $serverInstance -Database $databaseName -Query $query -ErrorAction Stop

        if ($null -eq $result -or $result.Count -eq 0) {
            Write-Host "No data returned from the query or query returned a null result." -ForegroundColor Red
            return
        }

        Write-Host "Query result: $($result | Format-Table -AutoSize | Out-String)" -ForegroundColor Yellow

        # Extract the actual message from the result object
        $tableExistsMessage = $result | Select-Object -ExpandProperty Column1
        Write-Host "Extracted Message: '$tableExistsMessage'" -ForegroundColor Yellow

        if ([string]::IsNullOrWhiteSpace($tableExistsMessage)) {
            Write-Host "Extracted Message is null or whitespace." -ForegroundColor Red
            return
        }

        if ($tableExistsMessage.Trim() -eq 'Table exists') {
            Write-Host "Verification successful: The table exists." -ForegroundColor Green
        }
        else {
            Write-Host "Verification failed: The table does not exist." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "An error occurred during the verification query execution." -ForegroundColor Red
        Write-Host $_.Exception.Message
        Exit 1
    }
}

# Function to start SQL Server Agent
function Start-SqlServerAgent {
    param (
        [bool]$DebugMode
    )

    # Verify if SQL Server Agent is running
    $agentServiceStatus = Get-Service -Name "SQLSERVERAGENT" -ErrorAction SilentlyContinue
    if ($agentServiceStatus -and $agentServiceStatus.Status -ne 'Running') {
        Write-Host "SQL Server Agent is not running. Attempting to start it..." -ForegroundColor Yellow
        try {
            Start-Service -Name "SQLSERVERAGENT"
            Write-Host "SQL Server Agent started successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to start SQL Server Agent." -ForegroundColor Red
            Write-Host "Error Details: $_"
            if ($DebugMode) { Write-Debug "Failed to start SQL Server Agent. Error details: $_" }
            Exit 1
        }
    }
    else {
        Write-Host "SQL Server Agent is already running." -ForegroundColor Green
    }
}

# Function to initialize the dbatools module
function Initialize-DbatoolsModule {
    # Print to the screen that the module loading process is starting
    Write-Host "Checking if module dbatools is already loaded..."

    # Check if the module is already loaded
    if (Get-Module -Name dbatools -ListAvailable) {
        Write-Host "Module dbatools is already loaded."
    }
    else {
        Write-Host "Loading module: dbatools..."
        try {
            # Load the module
            Import-Module dbatools -ErrorAction Stop

            # Confirm that the module has been loaded
            Write-Host "Module dbatools loaded successfully."
        }
        catch {
            # Handle the error if the module fails to load
            Write-Host "Error: Failed to load module dbatools." -ForegroundColor Red
            Write-Host "Error details: $_"
            if ($debugMode) { Write-Debug "Failed to load module dbatools. Error details: $_" }

            # Provide information on how to install dbatools
            Write-Host "Installation of dbatools" -ForegroundColor Yellow
            Write-Host "https://dbatools.io/download/" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Offline Installation of dbatools 2.0 with the dbatools.library Dependency" -ForegroundColor Yellow
            Write-Host "https://blog.netnerds.net/2023/04/offline-install-of-dbatools-and-dbatools-library/" -ForegroundColor Yellow

            Exit 1
        }
    }
}

# Function to read passwords and store them securely
function Read-Passwords {
    # Show progress message
    Show-ProgressMessage -message "Prompting for input of passwords..."
    try {
        # Get secure passwords and create SQL credentials
        Get-SecurePasswords
        New-SqlCredentials
    }
    catch {
        # Handle the error if prompting for passwords fails
        Write-Host "Failed to prompt for input of passwords." -ForegroundColor Red
        Write-Host "Error details: $_"
        Exit 1
    }

    # Store passwords in the config object
    $config.SqlSvcPassword = $sqlServiceCredential.GetNetworkCredential().Password
    $config.AgtSvcPassword = $sqlAgentCredential.GetNetworkCredential().Password
    $config.SaPwd = $saCredential.GetNetworkCredential().Password
}

# Function to test TempDb sizes
function Test-TempDbSizes {
    param (
        [int]$TempdbDataFileSize,
        [int]$TempdbLogFileSize
    )

    if ($TempdbDataFileSize -lt 512) {
        throw "TempdbDataFileSize must be at least 512 MB."
    }
    if ($TempdbLogFileSize -lt 64) {
        throw "TempdbLogFileSize must be at least 64 MB."
    }
}

# Function to set variables and verification query
function Set-Variables {
    param (
        [string]$scriptDir,
        [string]$tableName
    )

    # Define variables
    [string]$scriptDirectory = "$scriptDir\Sql"
    [string]$orderFile = "$scriptDir\order.txt"

    # Verification query
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

    Show-ProgressMessage -message "Restarting SQL Server services to apply settings..."
    try {
        Restart-DbaService -SqlInstance $server -Type Engine, Agent -Confirm:$false
        Write-Host "SQL Server services restarted successfully." -ForegroundColor Green
        if ($debugMode) { Write-Debug "SQL Server services restarted successfully on server $server" }
    }
    catch {
        Write-Host "Failed to restart SQL Server services." -ForegroundColor Red
        Write-Host "Error Details: $_"
        if ($debugMode) { Write-Debug "Failed to restart SQL Server services on server $server. Error details: $_" }
        Exit 1
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

        # Check if installer path exists
        if (-Not (Test-Path -Path $setupPath)) {
            Write-Host "Installer path not found: $setupPath" -ForegroundColor Red
            Exit 1
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
        Write-Host "Failed to determine installer details." -ForegroundColor Red
        Write-Host "Error details: $_"
        Exit 1
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

    # Read order file
    $orderList = Get-Content -Path $orderFile

    foreach ($entry in $orderList) {
        # Split the database and file name
        $parts = $entry -split ":"
        $databaseName = $parts[0]
        $fileName = $parts[1]
        $filePath = Join-Path -Path $scriptDirectory -ChildPath $fileName

        if (Test-Path $filePath) {
            # Read the contents of the SQL file
            $scriptContent = Get-Content -Path $filePath -Raw

            try {
                # Invoke the SQL script against the specified database
                Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $scriptContent
                Write-Output "Successfully executed script: $fileName on database: $databaseName"
                if ($debugMode) { Write-Debug "Successfully executed script: $fileName on database: $databaseName" }
            }
            catch {
                Write-Output "Failed to execute script: $fileName on database: $databaseName"
                Write-Output $_.Exception.Message
                if ($debugMode) { Write-Debug "Failed to execute script: $fileName on database: $databaseName. Error: $_" }
                Exit 1
            }
        }
        else {
            Write-Output "File not found: $fileName"
            if ($debugMode) { Write-Debug "File not found: $fileName in path: $filePath" }
            Exit 1
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

    # SQL Server Installation Parameters
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
        SqlCollation                  = $SqlCollation
        AdminAccount                  = $AdminAccount
        UpdateSourcePath              = $updateSourcePath
        PerformVolumeMaintenanceTasks = $true
        AuthenticationMode            = "Mixed"
        EngineCredential              = $sqlServiceCredential
        Port                          = $Port
        SaCredential                  = $saCredential
        Configuration                 = $config
    }

    # Conditionally add the PID to the install parameters if it's needed
    if ($edition -ne "Developer") {
        if ($null -eq $productKey) {
            Write-Host "Product key is required for Standard and Enterprise editions." -ForegroundColor Red
            if ($debugMode) { Write-Debug "Product key is required for Standard and Enterprise editions." }
            Exit 1
        }
        $installParams.Pid = $productKey
    }

    # Set verbose preference based on DebugMode
    if ($debugMode) {
        $VerbosePreference = "Continue"
    }
    else {
        $VerbosePreference = "SilentlyContinue"
    }

    # Show progress message for starting SQL Server installation
    Show-ProgressMessage -message "Starting SQL Server installation..."
    try {
        Invoke-Command {
            Install-DbaInstance @installParams
        } -OutVariable installOutput -ErrorVariable installError -WarningVariable installWarning -Verbose:$false
    }
    catch {
        Write-Host "SQL Server installation failed with an error. Exiting script." -ForegroundColor Red
        Write-Host "Error Details: $_"
        if ($debugMode) { Write-Debug "SQL Server installation failed. Error details: $_" }
        Exit 1
    }

    # Capture and suppress detailed output, only show if debugMode is enabled
    if ($debugMode) {
        Write-Host "Installation Output:"
        $installOutput
        Write-Host "Installation Errors:"
        $installError
        Write-Host "Installation Warnings:"
        $installWarning
    }

    # Check install warning for a reboot requirement message
    Test-RebootRequirement -warnings $installWarning
}

# Function to set SQL Server settings
function Set-SqlServerSettings {
    param (
        [string]$server,
        [bool]$debugMode
    )

    Show-ProgressMessage -message "Starting additional configuration steps..."

    # Log each configuration step with verbose and debug output
    Show-ProgressMessage -message "Configuring backup compression, optimize for ad hoc workloads, and remote admin connections..."
    Get-DbaSpConfigure -SqlInstance $server -Name 'backup compression default', 'optimize for ad hoc workloads', 'remote admin connections' |
    ForEach-Object {
        Set-DbaSpConfigure -SqlInstance $server -Name $_.Name -Value 1
        if ($debugMode) { Write-Debug "Configured $($_.Name) to 1 on server $server" }
    }

    Show-ProgressMessage -message "Setting cost threshold for parallelism..."
    Set-DbaSpConfigure -SqlInstance $server -Name 'cost threshold for parallelism' -Value 75
    if ($debugMode) { Write-Debug "Set 'cost threshold for parallelism' to 75 on server $server" }

    Show-ProgressMessage -message "Setting recovery interval (min)..."
    Set-DbaSpConfigure -SqlInstance $server -Name 'recovery interval (min)' -Value 60
    if ($debugMode) { Write-Debug "Set 'recovery interval (min)' to 60 on server $server" }

    Show-ProgressMessage -message "Configuring startup parameter for TraceFlag 3226..."
    Set-DbaStartupParameter -SqlInstance $server -TraceFlag 3226 -Confirm:$false
    if ($debugMode) { Write-Debug "Configured startup parameter TraceFlag 3226 on server $server" }

    Show-ProgressMessage -message "Setting max memory..."
    Set-DbaMaxMemory -SqlInstance $server
    if ($debugMode) { Write-Debug "Set max memory on server $server" }

    Show-ProgressMessage -message "Setting max degree of parallelism..."
    Set-DbaMaxDop -SqlInstance $server
    if ($debugMode) { Write-Debug "Set max degree of parallelism on server $server" }

    Show-ProgressMessage -message "Configuring power plan..."
    Set-DbaPowerPlan -ComputerName $server
    if ($debugMode) { Write-Debug "Configured power plan on server $server" }

    Show-ProgressMessage -message "Configuring error log settings..."
    Set-DbaErrorLogConfig -SqlInstance $server -LogCount 60 -LogSize 500
    if ($debugMode) { Write-Debug "Configured error log settings (LogCount: 60, LogSize: 500MB) on server $server" }

    Show-ProgressMessage -message "Configuring database file growth settings for 'master' database..."
    Set-DbaDbFileGrowth -SqlInstance $server -Database master -FileType Data -GrowthType MB -Growth 128
    Set-DbaDbFileGrowth -SqlInstance $server -Database master -FileType Log -GrowthType MB -Growth 64
    if ($debugMode) { Write-Debug "Configured 'master' database files growth settings (Data:128MB, Log: 64MB) on server $server" }

    Show-ProgressMessage -message "Configuring database file growth settings for 'msdb' database..."
    Set-DbaDbFileGrowth -SqlInstance $server -Database msdb -FileType Data -GrowthType MB -Growth 128
    Set-DbaDbFileGrowth -SqlInstance $server -Database msdb -FileType Log -GrowthType MB -Growth 64
    if ($debugMode) { Write-Debug "Configured 'msdb' database files growth settings (Data:128MB, Log: 64MB) on server $server" }

    Show-ProgressMessage -message "Configuring database file growth settings for 'model' database..."
    Set-DbaDbFileGrowth -SqlInstance $server -Database model -FileType Data -GrowthType MB -Growth 128
    Set-DbaDbFileGrowth -SqlInstance $server -Database model -FileType Log -GrowthType MB -Growth 64
    if ($debugMode) { Write-Debug "Configured 'model' database files growth settings (Data:128MB, Log: 64MB) on server $server" }

    Show-ProgressMessage -message "Configuring SQL Agent server settings..."
    try {
        Set-DbaAgentServer -SqlInstance $server -MaximumJobHistoryRows 0 -MaximumHistoryRows -1 -ReplaceAlertTokens Enabled
        if ($debugMode) { Write-Debug "Configured SQL Agent server settings on server $server" }
    }
    catch {
        Write-Host "Warning: Failed to configure SQL Agent server settings. Ensure 'Agent XPs' is enabled." -ForegroundColor Yellow
        Write-Host "Error details: $_"
        if ($debugMode) { Write-Debug "Failed to configure SQL Agent server settings on server $server. Error details: $_" }
        Exit 1
    }

    # Get the number of CPU cores
    $cpuCores = (Get-WmiObject -Class Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

    # Set the variable to the number of cores or 8, whichever is lower
    $maxCores = if ($cpuCores -gt 8) { 8 } else { $cpuCores }

    # Show progress message for configuring TempDB
    Show-ProgressMessage -message "Configuring TempDB..."
    try {
        # Configure TempDB with the determined number of cores
        Set-DbaTempDbConfig -SqlInstance $server -DataFileCount $maxCores -DataFileSize $TempdbDataFileSize -LogFileSize $TempdbLogFileSize -DataFileGrowth $TempdbDataFileGrowth -LogFileGrowth $TempdbLogFileGrowth -ErrorAction Stop
        if ($debugMode) { Write-Debug "Configured TempDB on server $server with $maxCores data files" }
    }
    catch {
        Write-Host "Warning: Failed to configure TempDB." -ForegroundColor Yellow
        Write-Host "Error details: $_"
        if ($debugMode) { Write-Debug "Failed to configure TempDB on server $server. Error details: $_" }
        Exit 1
    }

    Show-ProgressMessage -message "Additional configuration steps completed."
}

# Function to install SQL Server Management Studio if requested
function Install-SSMSIfRequested {
    param (
        [bool]$installSsms,
        [string]$ssmsInstallerPath,
        [bool]$debugMode
    )

    if ($installSsms) {
        # Check if SSMS is already installed
        if (Test-SsmsInstalled) {
            Write-Host "SQL Server Management Studio (SSMS) is already installed. Exiting script." -ForegroundColor Red
            if ($debugMode) { Write-Debug "SQL Server Management Studio (SSMS) is already installed." }
            Exit 0
        }

        Show-ProgressMessage -message "Installing SQL Server Management Studio (SSMS)..."
        Install-Ssms -installerPath $ssmsInstallerPath
    }
    else {
        Write-Host "SSMS installation not requested. Skipping SSMS installation." -ForegroundColor Yellow
        if ($debugMode) { Write-Debug "SSMS installation not requested. Skipping SSMS installation." }
    }
}

# Function to show final informational message
function Show-FinalMessage {
    Write-Host "SQL Server installation and configuration completed successfully." -ForegroundColor Green
    if ($debugMode) { 
        Write-Debug "SQL Server installation and configuration completed successfully on server $server" 
    }

    # Get SQL version directory from the installer details
    $sqlVersionDirectory = switch ($Version) {
        2016 { "130" }
        2017 { "140" }
        2019 { "150" }
        2022 { "160" }
        default { 
            Write-Host "Unsupported SQL Server version: $Version" -ForegroundColor Red
            if ($debugMode) { Write-Debug "Unsupported SQL Server version: $Version" }
            throw "Unsupported SQL Server version: $Version" 
        }
    }

    # Add an empty line for line break
    Write-Host ""
    # Add additional info for the end user when installation is complete
    Write-Host "Installation Complete! Here is some additional information:"
    Write-Host "- Log Files: Check the installation logs located at C:\Program Files\Microsoft SQL Server\$sqlVersionDirectory\Setup Bootstrap\Log"
    Write-Host "- Verification: Verify the installation by connecting to the SQL Server instance using SQL Server Management Studio (SSMS)"
    Write-Host "  or using the command: `sqlcmd -S <YourServerName> -Q 'SELECT @@VERSION'"
    Write-Host "- Post-Installation Steps: Ensure to review and implement security best practices, configure regular backups, and monitor your SQL Server instance."
    Write-Host "- Resources: For further assistance, refer to the official documentation: https://docs.microsoft.com/en-us/sql/sql-server/"
}


# Main Function to install and configure SQL Server
function Invoke-InstallSqlServer {
    # Initialize the dbatools module
    Initialize-DbatoolsModule

    # Set Variables for Script Execution and Configuration
    $variables = Set-Variables -scriptDir $scriptDir -tableName $tableName
    $scriptDirectory = $variables.scriptDirectory
    $orderFile = $variables.orderFile
    $verificationQuery = $variables.verificationQuery

    # Check if AgtSvcAccount is $null and set it to SqlSvcAccount if true
    if ($null -eq $config.AgtSvcAccount) {
        $config.AgtSvcAccount = $config.SqlSvcAccount
    }

    # Test TempDB sizes
    Test-TempDbSizes -TempdbDataFileSize $TempdbDataFileSize -TempdbLogFileSize $TempdbLogFileSize

    # Show progress message for verifying volume block sizes
    Show-ProgressMessage -message "Verifying volume block sizes..."
    $volumePaths = @(
        $config.SqlTempDbLogDir,
        $config.SqlTempDbDir,
        $SqlDataDir,
        $SqlLogDir,
        $SqlBackupDir
    )

    # Test volume block sizes and handle user decision if sizes are not correct
    if (-not (Test-VolumeBlockSize -paths $volumePaths)) {
        $userInput = Read-Host "One or more volumes do not use a 64 KB block size. Do you want to continue with the installation? (Y/N)"
        if ($userInput -ne 'Y') {
            Write-Host "Installation cancelled by user." -ForegroundColor Red
            if ($debugMode) { Write-Debug "User cancelled installation due to volume block size check failure." }
            Exit 1
        }
    }

    # Read passwords and store them securely
    Read-Passwords

    # Determine installer path, SQL version, and update directory
    $installerDetails = Get-SqlInstallerDetails -installerPath $sqlInstallerLocalPath -scriptDir $scriptDir

    $installerPath = $installerDetails.SetupPath
    $driveLetter = $installerDetails.DriveLetter
    $updateSourcePath = $installerDetails.UpdateSourcePath

    # Invoke SQL Server installation
    Invoke-SqlServerInstallation -installerPath $installerPath -updateSourcePath $updateSourcePath -driveLetter $driveLetter -server $server -debugMode $debugMode

    # Unmount ISO if it was used
    Dismount-IfIso -installerPath $sqlInstallerLocalPath

    # Invoke SQL scripts from the order file
    Invoke-SqlScriptsFromOrderFile -orderFile $orderFile -scriptDirectory $scriptDirectory -server $server -debugMode $debugMode

    # Show progress message for verifying SQL script execution
    Show-ProgressMessage -message "Verifying SQL script execution..."
    Test-SqlExecution -serverInstance $server -databaseName "master" -query $verificationQuery

    # Configure SQL Server settings
    Set-SqlServerSettings -server $server -debugMode $debugMode

    # Install SSMS if requested
    Install-SSMSIfRequested -installSsms $installSsms -ssmsInstallerPath $ssmsInstallerPath -debugMode $debugMode

    Show-ProgressMessage -message "Verifying if updates were applied..."
    Test-UpdatesApplied -updateSourcePath $updateSourcePath

    # Restart SQL Server services to apply settings
    Restart-SqlServices -server $server -debugMode $debugMode

    # Verify if SQL Server Agent is running
    Start-SqlServerAgent -DebugMode $debugMode

    # Show final informational message
    Show-FinalMessage
}

# Execute the main function
Invoke-InstallSqlServer
