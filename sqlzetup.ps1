# Configuration Variables
[string]$server = $env:COMPUTERNAME
[string]$edition = "Developer" # Options: Developer, Standard, Enterprise
[string]$productKey = $null
[bool]$InstallSSMS = $true
[bool]$DebugMode = $true
[string]$sqlInstallerLocalPath = "C:\Temp\sqlzetup\SQLServer2022-x64-ENU-Dev.iso"  # Update this path to your ISO or EXE file
[string]$tableName = "CommandLog"

# Configuration for paths
$config = @{
    SQLTEMPDBLOGDIR        = "e:\mssql\tempdblog"
    SQLTEMPDBDIR           = "e:\mssql\tempdbdata"
    BROWSERSVCSTARTUPTYPE  = "Disabled"
    SQLTEMPDBFILESIZE      = 8 # 1024 MB is max (for each file)
    SQLTEMPDBFILEGROWTH    = 64 # 1024 MB is max (for each file)
    SQLTEMPDBLOGFILESIZE   = 8 # 1024 MB is max (for each file)
    SQLTEMPDBLOGFILEGROWTH = 64 # 1024 MB is max (for each file)
    NPENABLED              = 0
    TCPENABLED             = 1
    SQLSVCACCOUNT          = "agdemo\sqlengine"
    SQLSVCPASSWORD         = $null
    AGTSVCACCOUNT          = "agdemo\SqlAgent"
    AGTSVCPASSWORD         = $null
    SAPWD                  = $null
}
$script:SSMSInstallerPath = "C:\Temp\sqlzetup\SSMS-Setup-ENU.exe"

# Function to show progress messages
function Show-ProgressMessage {
    param (
        [string]$Message
    )
    Write-Host "$Message"
    if ($DebugMode) {
        Write-Debug "$Message"
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
            if ($DebugMode) { Write-Debug "BlockSize for volume $drive is $blockSize instead of 65536." }
            $blockSizeOK = $false
        }
        else {
            Write-Host "Volume $drive uses a 64 KB block size." -ForegroundColor Green
        }
    }

    return $blockSizeOK
}

# Check block size of specified volumes before installation
$volumePaths = @(
    $config.SQLTEMPDBLOGDIR,
    $config.SQLTEMPDBDIR,
    "e:\mssql\data",
    "e:\mssql\log",
    "e:\mssql\backup"
)

Show-ProgressMessage -Message "Verifying volume block sizes..."
if (-not (Test-VolumeBlockSize -paths $volumePaths)) {
    $userInput = Read-Host "One or more volumes do not use a 64 KB block size. Do you want to continue with the installation? (Y/N)"
    if ($userInput -ne 'Y') {
        Write-Host "Installation cancelled by user." -ForegroundColor Red
        if ($DebugMode) { Write-Debug "User cancelled installation due to volume block size check failure." }
        Exit 1
    }
}

# Function to prompt for secure passwords
function Get-SecurePasswords {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "Get-SecurePasswords")]
    $global:saPassword = Read-Host -AsSecureString -Prompt "Enter the SA password"
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "Get-SecurePasswords")]
    $global:sqlServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server service account"
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "Get-SecurePasswords")]
    $global:sqlAgentServiceAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the SQL Server Agent service account"
}

# Function to create PSCredential objects
function New-SqlCredentials {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "New-SqlCredentials")]
    $global:saCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sa", $saPassword
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "New-SqlCredentials")]
    $global:sqlServiceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "agdemo\sqlengine", $sqlServiceAccountPassword
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Scope = "Function", Target = "New-SqlCredentials")]
    $global:sqlAgentCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "agdemo\SqlAgent", $sqlAgentServiceAccountPassword
}

# Prompt for input of passwords
Show-ProgressMessage -Message "Prompting for input of passwords..."
Get-SecurePasswords
New-SqlCredentials

$config.SQLSVCPASSWORD = $sqlServiceCredential.GetNetworkCredential().Password
$config.AGTSVCPASSWORD = $sqlAgentCredential.GetNetworkCredential().Password
$config.SAPWD = $saCredential.GetNetworkCredential().Password

# Function to mount ISO and get setup.exe path
function Mount-IsoAndGetSetupPath {
    param (
        [string]$isoPath
    )

    if (-Not (Test-Path -Path $isoPath)) {
        Write-Host "ISO file not found at path: $isoPath" -ForegroundColor Red
        if ($DebugMode) { Write-Debug "ISO file not found at path: $isoPath" }
        Exit 1
    }

    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    $setupPath = "$($driveLetter):\setup.exe"

    Write-Verbose "Mounted ISO at $driveLetter and found setup.exe at $setupPath"
    if ($DebugMode) { Write-Debug "Mounted ISO at $driveLetter and found setup.exe at $setupPath" }

    return $setupPath, $driveLetter
}

# Function to unmount ISO
function Dismount-Iso {
    param (
        [string]$isoPath
    )

    $diskImage = Get-DiskImage -ImagePath $isoPath
    Dismount-DiskImage -ImagePath $diskImage.ImagePath

    Write-Verbose "Unmounted ISO at $($diskImage.DevicePath)"
    if ($DebugMode) { Write-Debug "Unmounted ISO at $($diskImage.DevicePath)" }
}

# Function to determine installer path based on file type
function Get-InstallerPath {
    param (
        [string]$installerPath
    )

    $fileExtension = [System.IO.Path]::GetExtension($installerPath).ToLower()

    Write-Verbose "Installer file extension: $fileExtension"
    if ($DebugMode) { Write-Debug "Installer file extension: $fileExtension" }

    if ($fileExtension -eq ".iso") {
        return Mount-IsoAndGetSetupPath -isoPath $installerPath
    }
    elseif ($fileExtension -eq ".exe") {
        return $installerPath, ""
    }
    else {
        Write-Host "Unsupported file type: $fileExtension. Please provide a path to an .iso or .exe file." -ForegroundColor Red
        if ($DebugMode) { Write-Debug "Unsupported file type: $fileExtension" }
        Exit 1
    }
}

$installerDetails = Get-InstallerPath -installerPath $sqlInstallerLocalPath
$installerPath = $installerDetails[0]
$driveLetter = $installerDetails[1]

# Function to get SQL Server version from the installer
function Get-SQLVersion {
    param (
        [string]$installerPath
    )

    if (Test-Path -Path $installerPath) {
        $versionInfo = (Get-Item $installerPath).VersionInfo
        return $versionInfo.ProductVersion
    }
    else {
        Write-Host "Installer not found at $installerPath" -ForegroundColor Red
        if ($DebugMode) { Write-Debug "Installer not found at $installerPath" }
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
            if ($DebugMode) { Write-Debug "Unsupported SQL Server version: $version" }
            throw "Unsupported SQL Server version: $version" 
        }
    }
}

$sqlVersion = Get-SQLVersion -installerPath $installerPath
$updateDirectory = Get-UpdateDirectory -version $sqlVersion
$updateSourcePath = "C:\Temp\sqlzetup\Updates\$updateDirectory"

$installparams = @{
    SqlInstance                   = $server
    Version                       = 2022
    Verbose                       = $true
    Confirm                       = $false
    Feature                       = "Engine"
    InstancePath                  = "C:\mssql"
    DataPath                      = "e:\mssql\data"
    LogPath                       = "e:\mssql\log"
    BackupPath                    = "e:\mssql\backup"
    Path                          = "${driveLetter}:\"
    InstanceName                  = "MSSQLSERVER"
    AgentCredential               = $sqlAgentCredential
    SqlCollation                  = "Finnish_Swedish_CI_AS"
    AdminAccount                  = "agdemo\sqlgroup"
    UpdateSourcePath              = $updateSourcePath
    PerformVolumeMaintenanceTasks = $true
    AuthenticationMode            = "Mixed"
    EngineCredential              = $sqlServiceCredential
    Port                          = 1433
    SaCredential                  = $saCredential
    Configuration                 = $config
}

# Conditionally add the PID to the install parameters if it's needed
if ($edition -ne "Developer") {
    if ($null -eq $productKey) {
        Write-Host "Product key is required for Standard and Enterprise editions." -ForegroundColor Red
        if ($DebugMode) { Write-Debug "Product key is required for Standard and Enterprise editions." }
        throw "Product key is required for Standard and Enterprise editions."
    }
    $installparams.PID = $productKey
}

# Set verbose preference based on DebugMode
if ($DebugMode) {
    $VerbosePreference = "Continue"
}

# Function to check if SSMS is installed
function Test-SSMSInstalled {
    param (
        [string]$SSMSVersion = "18"
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
            if ($DebugMode) { Write-Debug "SSMS installed programs found in registry path: $registryPath" }
            foreach ($program in $installedPrograms) {
                Write-Host "Name: $($program.DisplayName)"
                Write-Host "Version: $($program.DisplayVersion)"
            }
            return $true
        }
    }
    
    Write-Host "SSMS is not installed."
    if ($DebugMode) { Write-Debug "SSMS is not installed in any of the checked registry paths." }
    return $false
}

# Function to install SQL Server Management Studio (SSMS)
function Install-SSMS {
    param (
        [string]$installerPath
    )

    $params = "/Install /Quiet"

    Start-Process -FilePath $installerPath -ArgumentList $params -Wait
    Write-Host "SSMS installation completed." -ForegroundColor Green
    if ($DebugMode) { Write-Debug "SSMS installation completed using installer path: $installerPath" }
}

# Set installer path
Show-ProgressMessage -Message "Determining installer path..."
Show-ProgressMessage -Message "Installer path determined: $installerPath"

Show-ProgressMessage -Message "Starting SQL Server installation..."
try {
    Invoke-Command {
        Install-DbaInstance @installparams
    } -OutVariable installOutput -ErrorVariable installError -WarningVariable installWarning
}
catch {
    Write-Host "SQL Server installation failed with an error. Exiting script." -ForegroundColor Red
    Write-Host "Error Details: $_"
    if ($DebugMode) { Write-Debug "SQL Server installation failed. Error details: $_" }
    Exit 1
}

# Output captured information for troubleshooting
Write-Host "Installation Output:"
$installOutput
Write-Host "Installation Errors:"
$installError
Write-Host "Installation Warnings:"
$installWarning

# Check install warning for a reboot requirement message
if ($installWarning -like "*reboot*") {
    Write-Host "SQL Server installation requires a reboot." -ForegroundColor Red
    if ($DebugMode) { Write-Debug "SQL Server installation requires a reboot." }
    
    $userInput = Read-Host "SQL Server installation requires a reboot. Do you want to reboot now? (Y/N)"
    if ($userInput -eq 'Y') {
        Restart-Computer -Force
    }
    else {
        Write-Host "Please reboot the computer manually to complete the installation." -ForegroundColor Yellow
        Exit 1
    }
}

# Unmount ISO if it was used
if ([System.IO.Path]::GetExtension($sqlInstallerLocalPath).ToLower() -eq ".iso") {
    Dismount-Iso -isoPath $sqlInstallerLocalPath
}

# New solution for running SQL scripts based on order.txt
# Define variables
[string]$scriptDirectory = "C:\Temp\sqlzetup\Sql"
[string]$orderFile = "C:\Temp\sqlzetup\order.txt"

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
            # Execute the SQL script against the specified database
            Invoke-DbaQuery -SqlInstance $server -Database $databaseName -Query $scriptContent
            Write-Output "Successfully executed script: $fileName on database: $databaseName"
            if ($DebugMode) { Write-Debug "Successfully executed script: $fileName on database: $databaseName" }
        }
        catch {
            Write-Output "Failed to execute script: $fileName on database: $databaseName"
            Write-Output $_.Exception.Message
            if ($DebugMode) { Write-Debug "Failed to execute script: $fileName on database: $databaseName. Error: $_" }
        }
    }
    else {
        Write-Output "File not found: $fileName"
        if ($DebugMode) { Write-Debug "File not found: $fileName in path: $filePath" }
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
    }
}

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

Show-ProgressMessage -Message "Verifying SQL script execution..."
Test-SqlExecution -serverInstance $server -databaseName "master" -query $verificationQuery

# Additional Configuration Steps
Show-ProgressMessage -Message "Starting additional configuration steps..."

# Log each configuration step with verbose and debug output
Show-ProgressMessage -Message "Configuring backup compression, optimize for ad hoc workloads, and remote admin connections..."
Get-DbaSpConfigure -SqlInstance $server -Name 'backup compression default', 'optimize for ad hoc workloads', 'remote admin connections' |
ForEach-Object {
    Write-Verbose "Setting $($_.Name) to 1"
    Set-DbaSpConfigure -SqlInstance $server -Name $_.Name -Value 1
    if ($DebugMode) { Write-Debug "Configured $($_.Name) to 1 on server $server" }
}

Show-ProgressMessage -Message "Setting cost threshold for parallelism..."
Set-DbaSpConfigure -SqlInstance $server -Name 'cost threshold for parallelism' -Value 75
if ($DebugMode) { Write-Debug "Set 'cost threshold for parallelism' to 75 on server $server" }

Show-ProgressMessage -Message "Setting recovery interval (min)..."
Set-DbaSpConfigure -SqlInstance $server -Name 'recovery interval (min)' -Value 60
if ($DebugMode) { Write-Debug "Set 'recovery interval (min)' to 60 on server $server" }

Show-ProgressMessage -Message "Configuring startup parameter for TraceFlag 3226..."
Set-DbaStartupParameter -SqlInstance $server -TraceFlag 3226 -Confirm:$false
if ($DebugMode) { Write-Debug "Configured startup parameter TraceFlag 3226 on server $server" }

Show-ProgressMessage -Message "Setting max memory..."
Set-DbaMaxMemory -SqlInstance $server
if ($DebugMode) { Write-Debug "Set max memory on server $server" }

Show-ProgressMessage -Message "Setting max degree of parallelism..."
Set-DbaMaxDop -SqlInstance $server
if ($DebugMode) { Write-Debug "Set max degree of parallelism on server $server" }

Show-ProgressMessage -Message "Configuring power plan..."
Set-DbaPowerPlan -ComputerName $server
if ($DebugMode) { Write-Debug "Configured power plan on server $server" }

Show-ProgressMessage -Message "Configuring error log settings..."
Set-DbaErrorLogConfig -SqlInstance $server -LogCount 60 -LogSize 500
if ($DebugMode) { Write-Debug "Configured error log settings (LogCount: 60, LogSize: 500MB) on server $server" }

Show-ProgressMessage -Message "Configuring database file growth settings for 'master' database..."
Set-DbaDbFileGrowth -SqlInstance $server -Database master -FileType Data -GrowthType MB -Growth 128
Set-DbaDbFileGrowth -SqlInstance $server -Database master -FileType Log -GrowthType MB -Growth 64
if ($DebugMode) { Write-Debug "Configured 'master' database files growth settings (Data:128MB, Log: 64MB) on server $server" }

Show-ProgressMessage -Message "Configuring database file growth settings for 'msdb' database..."
Set-DbaDbFileGrowth -SqlInstance $server -Database msdb -FileType Data -GrowthType MB -Growth 128
Set-DbaDbFileGrowth -SqlInstance $server -Database msdb -FileType Log -GrowthType MB -Growth 64
if ($DebugMode) { Write-Debug "Configured 'msdb' database files growth settings (Data:128MB, Log: 64MB) on server $server" }

Show-ProgressMessage -Message "Configuring database file growth settings for 'model' database..."
Set-DbaDbFileGrowth -SqlInstance $server -Database model -FileType Data -GrowthType MB -Growth 128
Set-DbaDbFileGrowth -SqlInstance $server -Database model -FileType Log -GrowthType MB -Growth 64
if ($DebugMode) { Write-Debug "Configured 'model' database files growth settings (Data:128MB, Log: 64MB) on server $server" }

Show-ProgressMessage -Message "Configuring SQL Agent server settings..."
Set-DbaAgentServer -SqlInstance $server -MaximumJobHistoryRows 0 -MaximumHistoryRows -1
if ($DebugMode) { Write-Debug "Configured SQL Agent server settings (MaximumJobHistoryRows: 0, MaximumHistoryRows: -1) on server $server" }

Show-ProgressMessage -Message "Additional configuration steps completed."

# Install SSMS if requested and SQL Server installation was successful
if ($InstallSSMS) {
    # Check if SSMS is already installed
    if (Test-SSMSInstalled) {
        Write-Host "SQL Server Management Studio (SSMS) is already installed. Exiting script." -ForegroundColor Red
        if ($DebugMode) { Write-Debug "SQL Server Management Studio (SSMS) is already installed." }
        Exit 0
    }

    Show-ProgressMessage -Message "Installing SQL Server Management Studio (SSMS)..."
    Install-SSMS -installerPath $SSMSInstallerPath
}
else {
    Write-Host "SSMS installation not requested. Skipping SSMS installation." -ForegroundColor Yellow
    if ($DebugMode) { Write-Debug "SSMS installation not requested. Skipping SSMS installation." }
}

# Function to verify if updates were applied
function Test-UpdatesApplied {
    param (
        [string]$updateSourcePath
    )

    $updateFiles = Get-ChildItem -Path $updateSourcePath -Filter *.exe
    if ($updateFiles.Count -eq 0) {
        Write-Host "No update files found in ${updateSourcePath}" -ForegroundColor Yellow
        if ($DebugMode) { Write-Debug "No update files found in ${updateSourcePath}" }
    }
    else {
        Write-Host "Update files found in ${updateSourcePath}:"
        foreach ($file in $updateFiles) {
            Write-Host "Update: $($file.Name)"
            if ($DebugMode) { Write-Debug "Update file found: $($file.Name)" }
        }
    }
}

Show-ProgressMessage -Message "Verifying if updates were applied..."
Test-UpdatesApplied -updateSourcePath $updateSourcePath
