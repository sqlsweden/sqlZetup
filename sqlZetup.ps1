function Install-SQLServer {
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

    The script assumes a consistent directory structure, with all necessary files organized within the `sqlZetup` folder. It dynamically adapts to the root location of this folder, allowing for flexible deployment.

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

.PARAMETER SqlZetupRoot
    Path to the root directory containing the SQL Server ISO, SSMS installer, and setup scripts.

.PARAMETER IsoFileName
    Name of the SQL Server ISO file.

.PARAMETER SsmsInstallerFileName
    Name of the SSMS installer file.

.PARAMETER Version
    The version of SQL Server to install (e.g., 2016, 2017, 2019, 2022).

.PARAMETER Edition
    The edition of SQL Server to install (e.g., Developer, Standard, Enterprise).

.PARAMETER ProductKey
    The product key for SQL Server installation. Required for Standard and Enterprise editions.

.PARAMETER Collation
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

.PARAMETER InstallSsms
    Indicates whether to install SQL Server Management Studio.

.PARAMETER DebugMode
    Enables debug mode for detailed logging.

.EXAMPLE
    Install-SQLServer -SqlZetupRoot "C:\Temp\sqlZetup" -IsoFileName "SQLServer2022-x64-ENU-Dev.iso" -SsmsInstallerFileName "SSMS-Setup-ENU.exe" -Version 2022 -Edition "Developer" -Collation "Finnish_Swedish_CI_AS" -SqlSvcAccount "agdemo\sqlengine" -AgtSvcAccount "agdemo\sqlagent" -AdminAccount "agdemo\sqlgroup" -SqlDataDir "E:\MSSQL\Data" -SqlLogDir "F:\MSSQL\Log" -SqlBackupDir "H:\MSSQL\Backup" -SqlTempDbDir "G:\MSSQL\Data" -TempdbDataFileSize 512 -TempdbDataFileGrowth 64 -TempdbLogFileSize 64 -TempdbLogFileGrowth 64 -Port 1433 -InstallSsms $true -DebugMode $false

.NOTES
    Author: Michael Pettersson, Cegal
    Version: 1.0
    License: MIT License
#>

    param (
        [string]$SqlZetupRoot = "C:\Temp\sqlZetup", # Update this path as necessary
        [string]$IsoFileName = "SQLServer2022-x64-ENU-Dev.iso", # Update this file name as necessary
        [string]$SsmsInstallerFileName = "SSMS-Setup-ENU.exe", # Update this file name as necessary
        [ValidateSet(2016, 2017, 2019, 2022)]
        [int]$Version = 2022,
        [ValidateSet("Developer", "Standard", "Enterprise")]
        [string]$Edition = "Developer",
        [string]$ProductKey = $null, # Add your product key if using Standard or Enterprise edition
        [string]$Collation = "Finnish_Swedish_CI_AS",
        [string]$SqlSvcAccount = "agdemo\sqlengine",
        [string]$AgtSvcAccount = "agdemo\sqlagent",
        [string]$AdminAccount = "agdemo\sqlgroup",
        [string]$SqlDataDir = "E:\MSSQL\Data",
        [string]$SqlLogDir = "F:\MSSQL\Log",
        [string]$SqlBackupDir = "H:\MSSQL\Backup",
        [string]$SqlTempDbDir = "G:\MSSQL\Data",
        [string]$SqlTempDbLog = $SqlLogDir,
        [ValidateRange(512, [int]::MaxValue)]
        [int]$TempdbDataFileSize = 512,
        [int]$TempdbDataFileGrowth = 64,
        [ValidateRange(64, [int]::MaxValue)]
        [int]$TempdbLogFileSize = 64,
        [int]$TempdbLogFileGrowth = 64,
        [int]$Port = 1433,
        [bool]$InstallSsms = $true,
        [bool]$DebugMode = $false
    )

    function Write-Message {
        param (
            [string]$Message,
            [string]$Type = "Info"
        )

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "$timestamp [$Type] $Message"
        Write-Host $logEntry

        if ($DebugMode) {
            Write-Debug $logEntry
        }
    }

    function Show-ProgressMessage {
        param (
            [string]$Activity,
            [string]$Status,
            [int]$PercentComplete
        )
        $progressParams = @{
            Activity        = $Activity
            Status          = $Status
            PercentComplete = $PercentComplete
        }
        Write-Progress @progressParams
        Write-Message -Message "$Activity - $Status ($PercentComplete`%)"
    }

    function Test-Volume {
        param (
            [string[]]$Paths
        )
        
        $drivesToCheck = $Paths | ForEach-Object { $_[0] + ':' } | Sort-Object -Unique

        foreach ($drive in $drivesToCheck) {
            if (-not (Test-Path -Path $drive)) {
                Write-Message -Message "Volume does not exist: $drive" -Type "Error"
                throw "Volume does not exist: $drive"
            }

            $blockSize = Get-WmiObject -Query "SELECT BlockSize FROM Win32_Volume WHERE DriveLetter = '$drive'" | Select-Object -ExpandProperty BlockSize
            if ($blockSize -ne 65536) {
                Write-Message -Message "Volume $drive does not use a 64 KB block size." -Type "Error"
                throw "Volume $drive does not use a 64 KB block size."
            }
            else {
                Write-Message -Message "Volume $drive uses a 64 KB block size." -Type "Info"
            }
        }
    }

    function Get-SecurePasswords {
        $global:SaPassword = Read-Host -AsSecureString -Prompt "Enter the SA password"
        $global:SqlServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server service account"
        $global:SqlAgentServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server Agent service account"
    }

    function New-SqlCredentials {
        $global:SaCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sa", $SaPassword
        $global:SqlServiceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $SqlSvcAccount, $SqlServiceAccountPassword
        $global:SqlAgentCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $AgtSvcAccount, $SqlAgentServiceAccountPassword
    }

    function Mount-IsoAndGetSetupPath {
        param (
            [string]$IsoPath
        )

        if (-Not (Test-Path -Path $IsoPath)) {
            Write-Message -Message "ISO file not found at path: $IsoPath" -Type "Error"
            throw "ISO file not found"
        }

        try {
            $mountResult = Mount-DiskImage -ImagePath $IsoPath -PassThru
            $driveLetter = ($mountResult | Get-Volume).DriveLetter
            $setupPath = "$($driveLetter):\setup.exe"
            Write-Message -Message "Mounted ISO at $driveLetter and found setup.exe at $setupPath" -Type "Info"
            return $setupPath, $driveLetter
        }
        catch {
            Write-Message -Message "Failed to mount ISO and get setup.exe path. Error details: $_" -Type "Error"
            throw
        }
    }

    function Dismount-Iso {
        param (
            [string]$IsoPath
        )

        try {
            $diskImage = Get-DiskImage -ImagePath $IsoPath
            Dismount-DiskImage -ImagePath $diskImage.ImagePath | Out-Null
            Write-Message -Message "Unmounted ISO at $($diskImage.DevicePath)" -Type "Info"
        }
        catch {
            Write-Message -Message "Failed to unmount ISO. Error details: $_" -Type "Error"
            throw
        }
    }

    function Get-InstallerPath {
        param (
            [string]$InstallerPath
        )

        $fileExtension = [System.IO.Path]::GetExtension($InstallerPath).ToLower()
        Write-Message -Message "Installer file extension: $fileExtension" -Type "Info"

        if ($fileExtension -eq ".iso") {
            return Mount-IsoAndGetSetupPath -IsoPath $InstallerPath
        }
        else {
            Write-Message -Message "Unsupported file type: $fileExtension. Please provide a path to an .iso file." -Type "Error"
            throw "Unsupported file type"
        }
    }

    function Get-SqlVersion {
        param (
            [string]$InstallerPath
        )

        if (Test-Path -Path $InstallerPath) {
            $versionInfo = (Get-Item $InstallerPath).VersionInfo
            return $versionInfo.ProductVersion
        }
        else {
            Write-Message -Message "Installer not found at $InstallerPath" -Type "Error"
            throw "Installer not found"
        }
    }

    function Get-UpdateDirectory {
        param (
            [string]$Version
        )

        switch ($Version.Split('.')[0]) {
            '13' { return "2016" }
            '14' { return "2017" }
            '15' { return "2019" }
            '16' { return "2022" }
            default { 
                Write-Message -Message "Unsupported SQL Server version: $Version" -Type "Error"
                throw "Unsupported SQL Server version" 
            }
        }
    }

    function Test-RebootRequirement {
        param (
            [string]$Warnings
        )

        if ($Warnings -like "*reboot*") {
            Write-Message -Message "SQL Server installation requires a reboot." -Type "Warning"
            
            try {
                $userInput = Read-Host "SQL Server installation requires a reboot. Do you want to reboot now? (Y/N)"
                if ($userInput -eq 'Y') {
                    Restart-Computer -Force
                }
                else {
                    Write-Message -Message "Please reboot the computer manually to complete the installation." -Type "Warning"
                    throw "Reboot required"
                }
            }
            catch {
                Write-Message -Message "An error occurred while attempting to prompt for a reboot. Error details: $_" -Type "Error"
                throw
            }
        }
    }

    function Test-SsmsInstalled {
        param (
            [string]$SsmsVersion = "18"
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
                Write-Message -Message "SSMS is installed:" -Type "Info"
                foreach ($program in $installedPrograms) {
                    Write-Message -Message "Name: $($program.DisplayName)" -Type "Info"
                    Write-Message -Message "Version: $($program.DisplayVersion)" -Type "Info"
                }
                return $true
            }
        }
        
        Write-Message -Message "SSMS is not installed." -Type "Warning"
        return $false
    }

    function Install-Ssms {
        param (
            [string]$InstallerPath
        )

        $params = "/Install /Quiet"

        try {
            Start-Process -FilePath $InstallerPath -ArgumentList $params -Wait | Out-Null
            Write-Message -Message "SSMS installation completed." -Type "Info"
        }
        catch {
            Write-Message -Message "SSMS installation failed. Error details: $_" -Type "Error"
            throw
        }
    }

    function Test-UpdatesApplied {
        param (
            [string]$UpdateSourcePath
        )

        $updateFiles = Get-ChildItem -Path $UpdateSourcePath -Filter *.exe
        if ($updateFiles.Count -eq 0) {
            Write-Message -Message "No update files found in ${UpdateSourcePath}" -Type "Warning"
        }
        else {
            Write-Message -Message "Update files found in ${UpdateSourcePath}:" -Type "Info"
            foreach ($file in $updateFiles) {
                Write-Message -Message "Update: $($file.Name)" -Type "Info"
            }
        }
    }

    function Test-SqlExecution {
        param (
            [string]$ServerInstance,
            [string]$DatabaseName,
            [string]$Query
        )

        try {
            Write-Message -Message "Executing query on server: $ServerInstance, database: $DatabaseName" -Type "Info"
            $result = Invoke-DbaQuery -SqlInstance $ServerInstance -Database $DatabaseName -Query $Query -ErrorAction Stop

            if ($null -eq $result -or $result.Count -eq 0) {
                Write-Message -Message "No data returned from the query or query returned a null result." -Type "Error"
                throw "Query returned null or no data"
            }

            $tableExistsMessage = $result | Select-Object -ExpandProperty Column1
            Write-Message -Message "Extracted Message: '$tableExistsMessage'" -Type "Info"

            if ([string]::IsNullOrWhiteSpace($tableExistsMessage)) {
                Write-Message -Message "Extracted Message is null or whitespace." -Type "Error"
                throw "Query result message is null or whitespace"
            }

            if ($tableExistsMessage.Trim() -eq 'Table exists') {
                Write-Message -Message "Verification successful: The table exists." -Type "Info"
            }
            else {
                Write-Message -Message "Verification failed: The table does not exist." -Type "Error"
                throw "Table does not exist"
            }
        }
        catch {
            Write-Message -Message "An error occurred during the verification query execution. Error details: $_" -Type "Error"
            throw
        }
    }

    function Start-SqlServerAgent {
        param (
            [bool]$DebugMode
        )

        $agentServiceStatus = Get-Service -Name "SQLSERVERAGENT" -ErrorAction SilentlyContinue
        if ($agentServiceStatus -and $agentServiceStatus.Status -ne 'Running') {
            Write-Message -Message "SQL Server Agent is not running. Attempting to start it..." -Type "Warning"
            try {
                Start-Service -Name "SQLSERVERAGENT" | Out-Null
                Write-Message -Message "SQL Server Agent started successfully." -Type "Info"
            }
            catch {
                Write-Message -Message "Failed to start SQL Server Agent. Error details: $_" -Type "Error"
                throw
            }
        }
        else {
            Write-Message -Message "SQL Server Agent is already running." -Type "Info"
        }
    }

    function Initialize-DbatoolsModule {
        Write-Message -Message "Checking if module dbatools is already loaded..." -Type "Info"

        if (Get-Module -Name dbatools -ListAvailable) {
            Write-Message -Message "Module dbatools is already loaded." -Type "Info"
        }
        else {
            Write-Message -Message "Loading module: dbatools..." -Type "Info"
            try {
                Import-Module dbatools -ErrorAction Stop | Out-Null
                Write-Message -Message "Module dbatools loaded successfully." -Type "Info"
            }
            catch {
                Write-Message -Message "Error: Failed to load module dbatools. Error details: $_" -Type "Error"
                throw
            }
        }
    }

    function Read-Passwords {
        Show-ProgressMessage -Activity "Preparation" -Status "Prompting for input of passwords" -PercentComplete 0
        try {
            Get-SecurePasswords
            New-SqlCredentials
            Show-ProgressMessage -Activity "Preparation" -Status "Passwords input completed" -PercentComplete 100
        }
        catch {
            Write-Message -Message "Failed to prompt for input of passwords. Error details: $_" -Type "Error"
            throw
        }
    }

    function Set-Variables {
        param (
            [string]$ScriptDir,
            [string]$TableName
        )

        [string]$scriptDirectory = "$ScriptDir\Sql"
        [string]$orderFile = "$ScriptDir\order.txt"

        [string]$verificationQuery = @"
IF EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = '$TableName')
BEGIN
    SELECT 'Table exists' AS Column1
END
ELSE
BEGIN
    SELECT 'Table does not exist' AS Column1
END
"@

        return @{
            ScriptDirectory   = $scriptDirectory
            OrderFile         = $orderFile
            VerificationQuery = $verificationQuery
        }
    }

    function Restart-SqlServices {
        param (
            [string]$Server,
            [bool]$DebugMode
        )

        Show-ProgressMessage -Activity "Finalizing" -Status "Restarting SQL Server services" -PercentComplete 0
        try {
            Restart-DbaService -SqlInstance $Server -Type Engine, Agent -Confirm:$false | Out-Null
            Write-Message -Message "SQL Server services restarted successfully." -Type "Info"
            Show-ProgressMessage -Activity "Finalizing" -Status "SQL Server services restarted" -PercentComplete 100
        }
        catch {
            Write-Message -Message "Failed to restart SQL Server services. Error details: $_" -Type "Error"
            throw
        }
    }

    function Get-SqlInstallerDetails {
        param (
            [string]$InstallerPath,
            [string]$ScriptDir
        )

        try {
            $installerDetails = Get-InstallerPath -InstallerPath $InstallerPath
            $setupPath = $installerDetails[0]
            $driveLetter = $installerDetails[1]

            if (-Not (Test-Path -Path $setupPath)) {
                Write-Message -Message "Installer path not found: $setupPath" -Type "Error"
                throw "Installer path not found"
            }

            $sqlVersion = Get-SqlVersion -InstallerPath $setupPath
            $updateDirectory = Get-UpdateDirectory -Version $sqlVersion
            $updateSourcePath = "$ScriptDir\Updates\$updateDirectory"

            return @{ 
                SetupPath        = $setupPath 
                DriveLetter      = $driveLetter 
                SqlVersion       = $sqlVersion 
                UpdateSourcePath = $updateSourcePath 
            }
        }
        catch {
            Write-Message -Message "Failed to determine installer details. Error details: $_" -Type "Error"
            throw
        }
    }

    function Dismount-IfIso {
        param (
            [string]$InstallerPath
        )

        if ([System.IO.Path]::GetExtension($InstallerPath).ToLower() -eq ".iso") {
            Dismount-Iso -IsoPath $InstallerPath
        }
    }

    function Invoke-SqlScriptsFromOrderFile {
        param (
            [string]$OrderFile,
            [string]$ScriptDirectory,
            [string]$Server,
            [bool]$DebugMode
        )

        $orderList = Get-Content -Path $OrderFile

        foreach ($entry in $orderList) {
            $parts = $entry -split ":"
            $databaseName = $parts[0]
            $fileName = $parts[1]
            $filePath = Join-Path -Path $ScriptDirectory -ChildPath $fileName

            if (Test-Path $filePath) {
                $scriptContent = Get-Content -Path $filePath -Raw

                try {
                    Invoke-DbaQuery -SqlInstance $Server -Database $databaseName -Query $scriptContent | Out-Null
                    Write-Message -Message "Successfully executed script: $fileName on database: $databaseName" -Type "Info"
                }
                catch {
                    Write-Message -Message "Failed to execute script: $fileName on database: $databaseName. Error details: $_" -Type "Error"
                    throw
                }
            }
            else {
                Write-Message -Message "File not found: $fileName" -Type "Error"
                throw "SQL script file not found"
            }
        }
    }

    function Invoke-SqlServerInstallation {
        param (
            [string]$InstallerPath,
            [string]$UpdateSourcePath,
            [string]$DriveLetter,
            [string]$Server,
            [bool]$DebugMode
        )
        
        $installParams = @{
            SqlInstance                   = $Server
            Version                       = $Version
            Verbose                       = $false
            Confirm                       = $false
            Feature                       = "Engine"
            InstancePath                  = "C:\Program Files\Microsoft SQL Server"
            DataPath                      = $SqlDataDir
            LogPath                       = $SqlLogDir
            BackupPath                    = $SqlBackupDir
            Path                          = "${DriveLetter}:\"
            InstanceName                  = "MSSQLSERVER"
            AgentCredential               = $SqlAgentCredential
            AdminAccount                  = $AdminAccount
            UpdateSourcePath              = $UpdateSourcePath
            PerformVolumeMaintenanceTasks = $true
            AuthenticationMode            = "Mixed"
            EngineCredential              = $SqlServiceCredential
            Port                          = $Port
            SaCredential                  = $SaCredential
            SqlCollation                  = $Collation
            Configuration                 = @{
                SqlTempdbFileCount    = 1
                SqlTempdbDir          = $SqlTempDbDir
                SqlTempdbLogDir       = $SqlTempDbLog
                BrowserSvcStartupType = "Disabled"
            }
        }

        if ($Edition -ne "Developer") {
            if ($null -eq $ProductKey) {
                Write-Message -Message "Product key is required for Standard and Enterprise editions." -Type "Error"
                throw "Product key required for selected edition"
            }
            $installParams.Pid = $ProductKey
        }

        if ($DebugMode) {
            $VerbosePreference = "Continue"
        }
        else {
            $VerbosePreference = "SilentlyContinue"
        }

        Show-ProgressMessage -Activity "Installation" -Status "Starting SQL Server installation" -PercentComplete 0
        try {
            Invoke-Command {
                Install-DbaInstance @installParams
            } -OutVariable InstallOutput -ErrorVariable InstallError -WarningVariable InstallWarning -Verbose:$false | Out-Null
            Show-ProgressMessage -Activity "Installation" -Status "SQL Server installation completed" -PercentComplete 100
        }
        catch {
            Write-Message -Message "SQL Server installation failed with an error. Exiting script. Error details: $_" -Type "Error"
            throw
        }

        if ($DebugMode) {
            Write-Message -Message "Installation Output: $InstallOutput" -Type "Info"
            Write-Message -Message "Installation Errors: $InstallError" -Type "Info"
            Write-Message -Message "Installation Warnings: $InstallWarning" -Type "Info"
        }

        Test-RebootRequirement -Warnings $InstallWarning
    }

    function Set-SqlServerSettings {
        param (
            [string]$Server,
            [bool]$DebugMode
        )

        Show-ProgressMessage -Activity "Configuration" -Status "Starting additional configuration steps" -PercentComplete 0

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring backup compression, optimize for ad hoc workloads, and remote admin connections" -PercentComplete 20
        Get-DbaSpConfigure -SqlInstance $Server -Name 'backup compression default', 'optimize for ad hoc workloads', 'remote admin connections' |
        ForEach-Object {
            Set-DbaSpConfigure -SqlInstance $Server -Name $_.Name -Value 1 | Out-Null
        }

        Show-ProgressMessage -Activity "Configuration" -Status "Setting cost threshold for parallelism" -PercentComplete 30
        Set-DbaSpConfigure -SqlInstance $Server -Name 'cost threshold for parallelism' -Value 75 | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Setting recovery interval (min)" -PercentComplete 40
        Set-DbaSpConfigure -SqlInstance $Server -Name 'recovery interval (min)' -Value 60 | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring startup parameter for TraceFlag 3226" -PercentComplete 50
        Set-DbaStartupParameter -SqlInstance $Server -TraceFlag 3226 -Confirm:$false | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Setting max memory" -PercentComplete 60
        Set-DbaMaxMemory -SqlInstance $Server | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Setting max degree of parallelism" -PercentComplete 70
        Set-DbaMaxDop -SqlInstance $Server | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring power plan" -PercentComplete 80
        Set-DbaPowerPlan -ComputerName $Server | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring error log settings" -PercentComplete 90
        Set-DbaErrorLogConfig -SqlInstance $Server -LogCount 60 -LogSize 500 | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring database file growth settings for 'master' database" -PercentComplete 91
        Set-DbaDbFileGrowth -SqlInstance $Server -Database master -FileType Data -GrowthType MB -Growth 128 | Out-Null
        Set-DbaDbFileGrowth -SqlInstance $Server -Database master -FileType Log -GrowthType MB -Growth 64 | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring database file growth settings for 'msdb' database" -PercentComplete 92
        Set-DbaDbFileGrowth -SqlInstance $Server -Database msdb -FileType Data -GrowthType MB -Growth 128 | Out-Null
        Set-DbaDbFileGrowth -SqlInstance $Server -Database msdb -FileType Log -GrowthType MB -Growth 64 | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring database file growth settings for 'model' database" -PercentComplete 93
        Set-DbaDbFileGrowth -SqlInstance $Server -Database model -FileType Data -GrowthType MB -Growth 128 | Out-Null
        Set-DbaDbFileGrowth -SqlInstance $Server -Database model -FileType Log -GrowthType MB -Growth 64 | Out-Null

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring SQL Agent server settings" -PercentComplete 94
        try {
            Set-DbaAgentServer -SqlInstance $Server -MaximumJobHistoryRows 0 -MaximumHistoryRows -1 -ReplaceAlertTokens Enabled | Out-Null
        }
        catch {
            Write-Message -Message "Warning: Failed to configure SQL Agent server settings. Ensure 'Agent XPs' is enabled. Error details: $_" -Type "Warning"
        }
        
        $cpuCores = (Get-WmiObject -Class Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $maxCores = if ($cpuCores -gt 8) { 8 } else { $cpuCores }

        Show-ProgressMessage -Activity "Configuration" -Status "Configuring TempDB" -PercentComplete 95
        try {
            Set-DbaTempDbConfig -SqlInstance $Server -DataFileCount $maxCores -DataFileSize $TempdbDataFileSize -LogFileSize $TempdbLogFileSize -DataFileGrowth $TempdbDataFileGrowth -LogFileGrowth $TempdbLogFileGrowth -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Message -Message "Warning: Failed to configure TempDB. Error details: $_" -Type "Warning"
        }

        Show-ProgressMessage -Activity "Configuration" -Status "Additional configuration steps completed" -PercentComplete 100
    }

    function Install-SsmsIfRequested {
        param (
            [bool]$InstallSsms,
            [string]$SsmsInstallerPath,
            [bool]$DebugMode
        )

        if ($InstallSsms) {
            if (Test-SsmsInstalled) {
                Write-Message -Message "SQL Server Management Studio (SSMS) is already installed. Exiting script." -Type "Error"
                throw "SSMS already installed"
            }

            Show-ProgressMessage -Activity "Installation" -Status "Installing SQL Server Management Studio (SSMS)" -PercentComplete 0
            Install-Ssms -InstallerPath $SsmsInstallerPath
            Show-ProgressMessage -Activity "Installation" -Status "SQL Server Management Studio (SSMS) installed" -PercentComplete 100
        }
        else {
            Write-Message -Message "SSMS installation not requested. Skipping SSMS installation." -Type "Warning"
        }
    }

    function Show-FinalMessage {
        Write-Message -Message "SQL Server installation and configuration completed successfully." -Type "Info"
        if ($DebugMode) { 
            Write-Message -Message "SQL Server installation and configuration completed successfully on server $Server" -Type "Info"
        }

        $sqlVersionDirectory = switch ($Version) {
            2016 { "130" }
            2017 { "140" }
            2019 { "150" }
            2022 { "160" }
            default { 
                Write-Message -Message "Unsupported SQL Server version: $Version" -Type "Error"
                throw "Unsupported SQL Server version" 
            }
        }

        Write-Message -Message "" -Type "Info"
        Write-Message -Message "Installation Complete! Here is some additional information:" -Type "Info"
        Write-Message -Message "----------------------------------------------------------------------------------------" -Type "Info"
        Write-Message -Message "- Log Files: Check the installation log located at:" -Type "Info"
        Write-Message -Message "  C:\Program Files\Microsoft SQL Server\$sqlVersionDirectory\Setup Bootstrap\Log\Summary.txt" -Type "Info"
        Write-Message -Message "- Setup Monitoring: Visit the following URL to find a script for manual setup." -Type "Info"
        Write-Message -Message "  https://github.com/sqlsweden/sqlZetup/blob/main/Monitoring/zetupMonitoring.sql" -Type "Info"
        Write-Message -Message "- Include the backup volume in the backup for the file level backup." -Type "Info"
        Write-Message -Message "- Exclude the database files and folders from the antivirus software if it's used." -Type "Info"
        Write-Message -Message "- Document the passwords used in this installation at the proper location." -Type "Info"
        Write-Message -Message "" -Type "Info"
    }

    function Test-Collation {
        param (
            [string]$Collation,
            [string]$ScriptDir
        )

        $collationFilePath = Join-Path -Path $ScriptDir -ChildPath "collation.txt"

        if (-Not (Test-Path -Path $collationFilePath)) {
            Write-Message -Message "Collation file not found at path: $collationFilePath" -Type "Error"
            throw "Collation file not found"
        }

        $validCollations = Get-Content -Path $collationFilePath

        if ($Collation -notin $validCollations) {
            Write-Message -Message "Invalid collation: $Collation. Please specify a valid collation." -Type "Error"
            throw "Invalid collation specified"
        }
    }

    function Invoke-InstallSqlServer {
        try {
            Show-ProgressMessage -Activity "Validation" -Status "Validating volume paths and block sizes" -PercentComplete 0
            Test-Volume -Paths @($SqlTempDbDir, $SqlTempDbLog, $SqlLogDir, $SqlDataDir, $SqlBackupDir)
            Show-ProgressMessage -Activity "Validation" -Status "Volume paths and block sizes validated" -PercentComplete 100

            Show-ProgressMessage -Activity "Validation" -Status "Validating collation" -PercentComplete 0
            Test-Collation -Collation $Collation -ScriptDir $ScriptDir
            Show-ProgressMessage -Activity "Validation" -Status "Collation validated" -PercentComplete 100

            Show-ProgressMessage -Activity "Initialization" -Status "Initializing dbatools module" -PercentComplete 0
            Initialize-DbatoolsModule
            Show-ProgressMessage -Activity "Initialization" -Status "dbatools module initialized" -PercentComplete 100

            Show-ProgressMessage -Activity "Preparation" -Status "Reading passwords" -PercentComplete 0
            Read-Passwords
            Show-ProgressMessage -Activity "Preparation" -Status "Passwords read" -PercentComplete 100

            Show-ProgressMessage -Activity "Installation" -Status "Determining installer path" -PercentComplete 0
            $sqlInstallerDetails = Get-SqlInstallerDetails -InstallerPath $sqlInstallerLocalPath -ScriptDir $ScriptDir
            $setupPath = $sqlInstallerDetails.SetupPath
            $driveLetter = $sqlInstallerDetails.DriveLetter
            $updateSourcePath = $sqlInstallerDetails.UpdateSourcePath

            Invoke-SqlServerInstallation -InstallerPath $setupPath -UpdateSourcePath $updateSourcePath -DriveLetter $driveLetter -Server $Server -DebugMode $DebugMode
            Dismount-IfIso -InstallerPath $sqlInstallerLocalPath

            Set-SqlServerSettings -Server $Server -DebugMode $DebugMode

            $variables = Set-Variables -ScriptDir $ScriptDir -TableName $TableName
            $scriptDirectory = $variables.ScriptDirectory
            $orderFile = $variables.OrderFile
            $verificationQuery = $variables.VerificationQuery

            Invoke-SqlScriptsFromOrderFile -OrderFile $orderFile -ScriptDirectory $scriptDirectory -Server $Server -DebugMode $DebugMode

            Test-SqlExecution -ServerInstance $Server -DatabaseName "DBAdb" -Query $verificationQuery

            Restart-SqlServices -Server $Server -DebugMode $DebugMode

            Install-SsmsIfRequested -InstallSsms $InstallSsms -SsmsInstallerPath $ssmsInstallerPath -DebugMode $DebugMode

            Show-FinalMessage
        }
        catch {
            Write-Message -Message "An error occurred during the SQL Server installation process. Error details: $_" -Type "Error"
            throw
        }
        finally {
            Write-Message -Message "Script execution completed." -Type "Info"
        }
    }

    $sqlInstallerLocalPath = Join-Path -Path $SqlZetupRoot -ChildPath $IsoFileName
    $ssmsInstallerPath = Join-Path -Path $SqlZetupRoot -ChildPath $SsmsInstallerFileName
    $scriptDir = $SqlZetupRoot
    $Server = $env:COMPUTERNAME
    $TableName = "CommandLog"

    Invoke-InstallSqlServer
}

Install-SQLServer -SqlZetupRoot "C:\Temp\sqlZetup" -IsoFileName "SQLServer2022-x64-ENU-Dev.iso" -SsmsInstallerFileName "SSMS-Setup-ENU.exe" -Version 2022 -Edition "Developer" -Collation "Finnish_Swedish_CI_AS" -SqlSvcAccount "agdemo\sqlengine" -AgtSvcAccount "agdemo\sqlagent" -AdminAccount "agdemo\sqlgroup" -SqlDataDir "E:\MSSQL\Data" -SqlLogDir "F:\MSSQL\Log" -SqlBackupDir "H:\MSSQL\Backup" -SqlTempDbDir "G:\MSSQL\Data" -TempdbDataFileSize 512 -TempdbDataFileGrowth 64 -TempdbLogFileSize 64 -TempdbLogFileGrowth 64 -Port 1433 -InstallSsms $true -DebugMode $false
