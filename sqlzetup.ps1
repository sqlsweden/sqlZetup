# Configuration Variables
[string]$server = $env:COMPUTERNAME
[string]$edition = "Developer" # Options: Developer, Standard, Enterprise
[string]$productKey = $null
[bool]$InstallSSMS = $true
[bool]$DebugMode = $False
[string]$sqlInstallerLocalPath = "C:\Temp\sqlzetup\SQLServer2022-x64-ENU-Dev.iso"  # Update this path to your ISO or EXE file
[string]$sqlScriptPath1 = "C:\Temp\sqlzetup\Sql\MaintenanceSolution.sql"
[string]$sqlScriptPath2 = "C:\Temp\sqlzetup\Sql\MaintenanceSolutionAgentJobs.sql"
[string]$databaseName = "Master"
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
        Write-Verbose "$Message"
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
        Exit 1
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
    $global:sqlServiceCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "agdemo\sqlengine", $sqlServiceAccountPassword
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
        Exit 1
    }

    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    $setupPath = "$($driveLetter):\setup.exe"

    Write-Verbose "Mounted ISO at $driveLetter and found setup.exe at $setupPath"

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
}

# Function to determine installer path based on file type
function Get-InstallerPath {
    param (
        [string]$installerPath
    )

    $fileExtension = [System.IO.Path]::GetExtension($installerPath).ToLower()

    Write-Verbose "Installer file extension: $fileExtension"

    if ($fileExtension -eq ".iso") {
        return Mount-IsoAndGetSetupPath -isoPath $installerPath
    }
    elseif ($fileExtension -eq ".exe") {
        return $installerPath, ""
    }
    else {
        Write-Host "Unsupported file type: $fileExtension. Please provide a path to an .iso or .exe file." -ForegroundColor Red
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
        default { throw "Unsupported SQL Server version: $version" }
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
            foreach ($program in $installedPrograms) {
                Write-Host "Name: $($program.DisplayName)"
                Write-Host "Version: $($program.DisplayVersion)"
            }
            return $true
        }
    }
    
    Write-Host "SSMS is not installed."
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
    Write-Host "SQL Server installation requires a reboot. Exiting script." -ForegroundColor Red
    Exit 1
}

# Unmount ISO if it was used
if ([System.IO.Path]::GetExtension($sqlInstallerLocalPath).ToLower() -eq ".iso") {
    Dismount-Iso -isoPath $sqlInstallerLocalPath
}

# Function to run a SQL script and verify success
function Invoke-SqlScript {
    param (
        [string]$serverInstance,
        [string]$databaseName,
        [string]$sqlScriptPath
    )
    
    try {
        Invoke-DbaQuery -SqlInstance $serverInstance -Database $databaseName -File $sqlScriptPath -Verbose
        Write-Host "SQL script $sqlScriptPath executed successfully."
    }
    catch {
        Write-Host "An error occurred while executing the SQL script $sqlScriptPath."
        Write-Host $_.Exception.Message
        return $false
    }
    return $true
}

# Function to verify execution by checking a specific condition, e.g., the existence of a table
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

# Run the first SQL script
if (Invoke-SqlScript -serverInstance $server -databaseName $databaseName -sqlScriptPath $sqlScriptPath1) {
    # Only run the second script if the first one was successful
    if (Invoke-SqlScript -serverInstance $server -databaseName $databaseName -sqlScriptPath $sqlScriptPath2) {
        Write-Host "Both scripts executed successfully."
    }
    else {
        Write-Host "Second script execution failed."
    }
}
else {
    Write-Host "First script execution failed."
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
Test-SqlExecution -serverInstance $server -databaseName $databaseName -query $verificationQuery

# Install SSMS if requested and SQL Server installation was successful
if ($InstallSSMS) {
    # Check if SSMS is already installed
    if (Test-SSMSInstalled) {
        Write-Host "SQL Server Management Studio (SSMS) is already installed. Exiting script." -ForegroundColor Red
        Exit 0
    }

    Show-ProgressMessage -Message "Installing SQL Server Management Studio (SSMS)..."
    Install-SSMS -installerPath $SSMSInstallerPath
}
else {
    Write-Host "SSMS installation not requested. Skipping SSMS installation." -ForegroundColor Yellow
}

# Function to verify if updates were applied
function Test-UpdatesApplied {
    param (
        [string]$updateSourcePath
    )

    $updateFiles = Get-ChildItem -Path $updateSourcePath -Filter *.exe
    if ($updateFiles.Count -eq 0) {
        Write-Host "No update files found in ${updateSourcePath}" -ForegroundColor Yellow
    }
    else {
        Write-Host "Update files found in ${updateSourcePath}:"
        foreach ($file in $updateFiles) {
            Write-Host "Update: $($file.Name)"
        }
    }
}

Show-ProgressMessage -Message "Verifying if updates were applied..."
Test-UpdatesApplied -updateSourcePath $updateSourcePath
