<#
.SYNOPSIS
    Script to install SQL Server Developer Edition instance using either an ISO or EXE installer, and optionally install SQL Server Management Studio (SSMS).

.DESCRIPTION
    This script performs the following actions:
    - Checks if the script is being run as an administrator.
    - Ensures the machine is part of a domain.
    - Checks if the specified SQL Server instance already exists.
    - Prompts the user for required passwords.
    - Calculates the number of TEMPDB files based on the number of CPU cores.
    - Determines the installer path based on the provided ISO or EXE file.
    - Executes the SQL Server installation with specified parameters.
    - Optionally installs SQL Server Management Studio (SSMS).
    - Verifies the installation and checks for logs in case of errors.
    - Sets the SQL Server instance port number if specified and verifies it is not already in use.

    This script installs SQL Server Developer Edition (2016, 2017, 2019, or 2022) and ensures that the installation directories are configured correctly.
    The script enforces the following conditions:
    - Installation directories must not be on the `C:` drive.
    - All installation directories must have a block size of 64 KB.

.PARAMETER sqlInstanceName
    The name of the SQL Server instance to be installed (e.g., "MSSQLSERVER" for default instance, "MYINSTANCE" for named instance).

.PARAMETER serviceDomainAccount
    The domain account for the SQL Server service.

.PARAMETER sqlInstallerLocalPath
    The local path to the SQL Server installer ISO or EXE file.

.PARAMETER SQLSYSADMINACCOUNTS
    The domain accounts to be added as SQL Server system administrators.

.PARAMETER SQLTEMPDBDIR
    The directory for SQL TEMPDB data files.

.PARAMETER SQLTEMPDBLOGDIR
    The directory for SQL TEMPDB log files.

.PARAMETER SQLUSERDBDIR
    The directory for SQL user database data files.

.PARAMETER SQLUSERDBLOGDIR
    The directory for SQL user database log files.

.PARAMETER SQLVersion
    The version of SQL Server to be installed (e.g., 2016, 2017, 2019, 2022).

.PARAMETER InstallSSMS
    Switch to indicate if SQL Server Management Studio (SSMS) should be installed.

.PARAMETER SSMSInstallerPath
    The local path to the SSMS installer EXE file.

.PARAMETER DebugMode
    Enables detailed logging and verbose output for debugging purposes.

.PARAMETER PortNumber
    The TCP port number to be used by the SQL Server instance.

.NOTES
    - This script must be run as an administrator.
    - This script only supports machines that are part of a domain.
    - Ensure the provided SQL Server installer path is valid and accessible.
    - Adjust the script parameters as necessary for your environment.

.REQUIREMENTS
    - SQL Server Developer Edition installer ISO or EXE file for the specified version.
    - The installation directories must be configured on partitions other than the `C:` drive.
    - The block size of the partitions used for installation must be 64 KB.

.EXAMPLE
    .\Install-SQLServer.ps1 -sqlInstanceName "SQL2022" -serviceDomainAccount "agdemo\SQLEngine" -sqlInstallerLocalPath "C:\Temp\SQLServerSetup.iso" -SQLSYSADMINACCOUNTS "agdemo\sqlgroup" -SQLTEMPDBDIR "D:\tempdbdata" -SQLTEMPDBLOGDIR "D:\tempdblog" -SQLUSERDBDIR "E:\userdbdata" -SQLUSERDBLOGDIR "E:\userdblog" -SQLVersion 2022 -InstallSSMS -SSMSInstallerPath "C:\Temp\SSMS-Setup-ENU.exe" -DebugMode $true -PortNumber 1433

    This example installs a SQL Server 2022 Developer Edition instance named "SQL2022" using the specified domain account and ISO file, adds the specified sysadmin accounts, sets the directories for TEMPDB and user databases, installs SSMS, enables debugging mode, and sets the TCP port number to 1433.
#>

# Configurable parameters
param(
    [string]$sqlInstanceName = "SQL2022_9", # Set the SQL Server instance name
    [string]$serviceDomainAccount = "agdemo\SQLEngine", # Set the domain account for SQL Server service
    [string]$sqlInstallerLocalPath = "C:\Temp\sqlsetup\SQLServer2022-x64-ENU-Dev.iso", # Set the local path to the SQL Server installer ISO or EXE
    [string]$SQLSYSADMINACCOUNTS = "agdemo\sqlgroup", # Set the domain accounts to be added as sysadmins
    [string]$SQLTEMPDBDIR = "e:\tempdbdata9", # Set the directory for SQL TEMPDB data files
    [string]$SQLTEMPDBLOGDIR = "e:\tempdblog9", # Set the directory for SQL TEMPDB log files
    [string]$SQLUSERDBDIR = "e:\userdbdata", # Set the directory for SQL user database data files
    [string]$SQLUSERDBLOGDIR = "e:\userdblog", # Set the directory for SQL user database log files
    [ValidateSet("2016", "2017", "2019", "2022")]
    [string]$SQLVersion = "2022", # Set the SQL Server version
    [switch]$InstallSSMS = $true, # Install SQL Server Management Studio
    [string]$SSMSInstallerPath = "C:\Temp\sqlsetup\SSMS-Setup-ENU.exe", # Set the local path to the SSMS installer EXE
    [switch]$DebugMode = $False, # Enable debugging mode
    [int]$PortNumber = 1933 # Set the TCP port number
)

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

# Function to check if the block size of a given drive is 64 KB
function Test-BlockSize {
    param (
        [string]$driveLetter
    )

    # Get the block size using Get-Partition and Get-Volume
    $partition = Get-Partition -DriveLetter $driveLetter.TrimEnd(':')
    $blockSize = $partition | Get-Volume | Select-Object -ExpandProperty AllocationUnitSize

    if ($blockSize -ne 65536) {
        Write-Host "The block size for drive $driveLetter is not 64 KB. Current block size: $($blockSize / 1024) KB" -ForegroundColor Red
        return $false
    }
    return $true
}

# Function to check if a port is already in use
function Test-PortInUse {
    param (
        [int]$port
    )

    $connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($connections) {
        Write-Host "Port $port is already in use." -ForegroundColor Red
        return $true
    }
    return $false
}

# Set verbose preference based on DebugMode
if ($DebugMode) {
    $VerbosePreference = "Continue"
}

# Function to show progress messages
function Show-ProgressMessage {
    <#
    .SYNOPSIS
        Displays a progress message to the console.
    .PARAMETER Message
        The message to display.
    #>
    param (
        [string]$Message
    )
    Write-Host "$Message"
    if ($DebugMode) {
        Write-Verbose "$Message"
    }
}

# Function to check if running as Administrator
function Test-Administrator {
    <#
    .SYNOPSIS
        Checks if the script is running as an administrator.
    #>
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Please run this script as an administrator!" -ForegroundColor Red
        Exit 1
    }
}

# Function to check if machine is domain connected
function Test-DomainConnection {
    <#
    .SYNOPSIS
        Checks if the machine is part of a domain.
    #>
    if (-not (Get-WmiObject -Class Win32_ComputerSystem).PartOfDomain) {
        Write-Host "This script only supports domain connected machines." -ForegroundColor Red
        Exit 1
    }
}

# Function to check if an instance exists by querying the registry
function Test-SqlInstanceExists {
    <#
    .SYNOPSIS
        Checks if the specified SQL Server instance already exists.
    .PARAMETER instanceName
        The name of the SQL Server instance to check.
    .OUTPUTS
        [bool] $true if the instance exists, $false otherwise.
    #>
    param (
        [string]$instanceName
    )
    $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
    if (Test-Path $regPath) {
        $instances = Get-ItemProperty -Path $regPath
        return $instances.PSObject.Properties.Name -contains $instanceName
    }
    else {
        return $false
    }
}

# Function to prompt for secure passwords
function Get-SecurePasswords {
    <#
    .SYNOPSIS
        Prompts the user for secure passwords.
    #>
    $global:saPassword = Read-Host -AsSecureString -Prompt "Enter the SA password"
    $global:serviceDomainAccountPassword = Read-Host -AsSecureString -Prompt "Enter the password for the domain account used for running SQL Server"
}

# Function to create PSCredential objects
function Create-SqlCredentials {
    <#
    .SYNOPSIS
        Creates PSCredential objects for the SQL Server service and SA account.
    #>
    $global:saCredential = New-Object System.Management.Automation.PSCredential -ArgumentList "sa", $saPassword
    $global:engineCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $serviceDomainAccount, $serviceDomainAccountPassword
    $global:agentCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $serviceDomainAccount, $serviceDomainAccountPassword
}

# Function to mount ISO and get setup.exe path
function Mount-IsoAndGetSetupPath {
    <#
    .SYNOPSIS
        Mounts the ISO file and retrieves the path to setup.exe.
    .PARAMETER isoPath
        The path to the ISO file.
    .OUTPUTS
        [string] The path to setup.exe within the mounted ISO.
    #>
    param (
        [string]$isoPath
    )

    $mountResult = Mount-DiskImage -ImagePath $isoPath -PassThru
    $driveLetter = ($mountResult | Get-Volume).DriveLetter
    $setupPath = "$($driveLetter):\setup.exe"

    Write-Verbose "Mounted ISO at $driveLetter and found setup.exe at $setupPath"

    return $setupPath
}

# Function to get the number of cores
function Get-NumberOfCores {
    <#
    .SYNOPSIS
        Retrieves the number of CPU cores on the machine.
    .OUTPUTS
        [int] The number of CPU cores.
    #>
    $processorInfo = Get-WmiObject -Class Win32_Processor
    $coreCount = ($processorInfo | Measure-Object -Property NumberOfCores -Sum).Sum

    Write-Verbose "Number of CPU cores: $coreCount"

    return $coreCount
}

# Function to handle installation logs
function Check-InstallationLogs {
    <#
    .SYNOPSIS
        Checks and displays the SQL Server installation logs in case of errors.
    #>
    $logVersionMap = @{
        "2016" = "130"
        "2017" = "140"
        "2019" = "150"
        "2022" = "160"
    }
    $logPath = "C:\Program Files\Microsoft SQL Server\$($logVersionMap[$SQLVersion])\Setup Bootstrap\Log"
    if (Test-Path $logPath) {
        Write-Host "Checking SQL Server setup log at: $logPath" -ForegroundColor Yellow
        $logFilePath = Join-Path -Path $logPath -ChildPath "Summary.txt"
        if (Test-Path $logFilePath) {
            Write-Host "SQL Server setup log file: $logFilePath" -ForegroundColor Yellow
            Write-Host "Log file content:" -ForegroundColor Yellow
            Get-Content -Path $logFilePath | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-Host "Summary log file not found in $logPath." -ForegroundColor Red
        }
    }
    else {
        Write-Host "Log path $logPath does not exist." -ForegroundColor Red
    }
}

# Function to determine installer path based on file type
function Get-InstallerPath {
    <#
    .SYNOPSIS
        Determines the installer path based on the provided ISO or EXE file.
    .PARAMETER installerPath
        The local path to the SQL Server installer ISO or EXE file.
    .OUTPUTS
        [string] The path to the setup executable.
    #>
    param (
        [string]$installerPath
    )

    $fileExtension = [System.IO.Path]::GetExtension($installerPath).ToLower()

    Write-Verbose "Installer file extension: $fileExtension"

    if ($fileExtension -eq ".iso") {
        return Mount-IsoAndGetSetupPath -isoPath $installerPath
    }
    elseif ($fileExtension -eq ".exe") {
        return $installerPath
    }
    else {
        Write-Host "Unsupported file type: $fileExtension. Please provide a path to an .iso or .exe file." -ForegroundColor Red
        Exit 1
    }
}

# Function to install SQL Server Management Studio (SSMS)
function Install-SSMS {
    <#
    .SYNOPSIS
        Installs SQL Server Management Studio (SSMS).
    #>
    param (
        [string]$installerPath
    )

    $params = "/Install /Quiet"

    Start-Process -FilePath $installerPath -ArgumentList $params -Wait
    Write-Host "SSMS installation completed." -ForegroundColor Green
}

# Function to set SQL Server port
function Set-SQLServerPort {
    param (
        [string]$sqlInstanceName,
        [int]$PortNumber
    )

    # Function to get SQL Server version
    function Get-SQLServerVersion {
        param (
            [string]$instanceName
        )
        $instanceRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
        $instanceID = (Get-ItemProperty -Path $instanceRegPath).$instanceName
        $versionRegPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceID\Setup"
        $version = (Get-ItemProperty -Path $versionRegPath -Name "Version").Version
        return $version
    }

    # Function to get SQL Server service name
    function Get-SQLServiceName {
        param (
            [string]$instanceName
        )
        $services = Get-Service | Where-Object { $_.DisplayName -like "*$instanceName*" }
        foreach ($service in $services) {
            if ($service.DisplayName -match $instanceName) {
                return $service.Name
            }
        }
        throw "Service name for instance '$instanceName' not found."
    }

    # Get the SQL Server version
    $sqlVersion = Get-SQLServerVersion -instanceName $sqlInstanceName

    # Determine the registry path based on the instance name and version
    if ($sqlInstanceName -eq "MSSQLSERVER") {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL$(($sqlVersion -replace '\.', '')).MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
    }
    else {
        $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
        $instanceID = (Get-ItemProperty -Path $regPath).$sqlInstanceName
        $regPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceID\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
    }

    # Change the port number and clear dynamic ports in the registry
    Set-ItemProperty -Path $regPath -Name TcpPort -Value $PortNumber
    Set-ItemProperty -Path $regPath -Name TcpDynamicPorts -Value ""

    Write-Output "Port number changed to $PortNumber for instance $sqlInstanceName in the registry and dynamic ports cleared."

    # Get the SQL Server service name
    $serviceName = Get-SQLServiceName -instanceName $sqlInstanceName

    # Restart the SQL Server service to apply changes
    Restart-Service -Name $serviceName -Force

    Write-Output "SQL Server service $serviceName has been restarted."
}

# Main script logic

# Ensure running as Administrator and domain connected
Test-Administrator
Test-DomainConnection

# Check if the SQL Server instance already exists
$instanceExists = Test-SqlInstanceExists -instanceName $sqlInstanceName

if ($instanceExists) {
    Write-Host "SQL Server instance $sqlInstanceName already exists. Installation aborted." -ForegroundColor Yellow
    Exit 0
}
else {
    Write-Host "SQL Server instance $sqlInstanceName does not exist. Proceeding with installation." -ForegroundColor Green
}

# Check block size for all relevant partitions and create directories if they do not exist
$partitionsToCheck = @($SQLTEMPDBDIR, $SQLTEMPDBLOGDIR, $SQLUSERDBDIR, $SQLUSERDBLOGDIR)
$installationNotAllowedOnC = $false

foreach ($path in $partitionsToCheck) {
    if (-not (Test-Path $path)) {
        Write-Host "Path $path does not exist. Creating directory..." -ForegroundColor Yellow
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
    
    $driveLetter = (Get-Item -Path $path).PSDrive.Name
    if ($driveLetter -eq "C") {
        Write-Host "Installation not allowed on drive C:. Path: $path. Installation aborted." -ForegroundColor Red
        $installationNotAllowedOnC = $true
    }
    elseif (-not (Test-BlockSize -driveLetter $driveLetter)) {
        Write-Host "Block size check failed for path: $path. Installation aborted." -ForegroundColor Red
        Exit 1
    }
}

if ($installationNotAllowedOnC) {
    Exit 1
}

Write-Host "All relevant partitions have a block size of 64 KB." -ForegroundColor Green

# Prompt for input of passwords
Show-ProgressMessage -Message "Prompting for input of passwords..."
Get-SecurePasswords
Create-SqlCredentials

# Calculate SQLTEMPDBFILECOUNT based on the number of cores
$numberOfCores = Get-NumberOfCores
$SQLTEMPDBFILECOUNT = if ($numberOfCores -gt 8) { 8 } else { $numberOfCores }

# Set installer path
Show-ProgressMessage -Message "Determining installer path..."
$installerPath = Get-InstallerPath -installerPath $sqlInstallerLocalPath

# Define the parameters in a hash table
$params = @{
    "QS"                            = $null
    "ACTION"                        = "Install"
    "FEATURES"                      = "SQLENGINE"
    "INSTANCENAME"                  = $sqlInstanceName
    "SQLSVCACCOUNT"                 = $serviceDomainAccount
    "SQLSVCPASSWORD"                = $engineCredential.GetNetworkCredential().Password
    "AGTSVCACCOUNT"                 = $serviceDomainAccount
    "AGTSVCPASSWORD"                = $agentCredential.GetNetworkCredential().Password
    "SAPWD"                         = $saCredential.GetNetworkCredential().Password
    "INDICATEPROGRESS"              = $null
    "SQLSYSADMINACCOUNTS"           = $SQLSYSADMINACCOUNTS
    "IAcceptSQLServerLicenseTerms"  = $null
    "UpdateEnabled"                 = "False"
    "SQLTELSVCSTARTUPTYPE"          = "Manual"
    "AGTSVCSTARTUPTYPE"             = "Automatic"
    "SQLCOLLATION"                  = "Finnish_Swedish_CI_AS"
    "SQLSVCINSTANTFILEINIT"         = "True"
    "TCPENABLED"                    = "1"
    "SQLTEMPDBFILECOUNT"            = $SQLTEMPDBFILECOUNT
    "SQLTEMPDBDIR"                  = $SQLTEMPDBDIR
    "SQLTEMPDBLOGDIR"               = $SQLTEMPDBLOGDIR
    "SQLTEMPDBFILESIZE"             = "64"
    "SQLTEMPDBLOGFILESIZE"          = "64"
    "SQLUSERDBDIR"                  = $SQLUSERDBDIR
    "SQLUSERDBLOGDIR"               = $SQLUSERDBLOGDIR
    "USESQLRECOMMENDEDMEMORYLIMITS" = $null
}

# Convert the hash table into a string of arguments
$argumentList = foreach ($key in $params.Keys) {
    if ($null -ne $params[$key]) { 
        "/$key=$($params[$key])" 
    }
    else { 
        "/$key" 
    }
} -join " "

# Execute the installer
Show-ProgressMessage -Message "Starting SQL Server installation..."

try {
    Start-Process -FilePath $installerPath -ArgumentList $argumentList -Wait -PassThru

    # Wait for a few seconds to allow the service to start
    Start-Sleep -Seconds 30

    # Verification
    Show-ProgressMessage -Message "Verifying SQL Server installation..."
    $serviceName = if ($sqlInstanceName -eq "MSSQLSERVER") { "MSSQLSERVER" } else { "MSSQL`$$sqlInstanceName" }

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') {
        Write-Host "SQL Server installation succeeded: Service $serviceName is $($service.Status)" -ForegroundColor Green
    }
    else {
        Write-Host "SQL Server installation failed: Service $serviceName does not exist or is not running." -ForegroundColor Red
        Check-InstallationLogs
    }
}
catch {
    Write-Host "An error occurred during SQL Server installation: $_" -ForegroundColor Red
    Check-InstallationLogs
    Exit 1
}

# Check if SSMS is already installed
if ($InstallSSMS -and (Test-SSMSInstalled)) {
    Write-Host "SQL Server Management Studio (SSMS) is already installed. Installation aborted." -ForegroundColor Red
    Exit 1
}

# Install SSMS if requested
if ($InstallSSMS) {
    Show-ProgressMessage -Message "Installing SQL Server Management Studio (SSMS)..."
    Install-SSMS -installerPath $SSMSInstallerPath
}

# Set the SQL Server port number after installation if needed
Show-ProgressMessage -Message "Setting SQL Server port number to $PortNumber..."
Set-SQLServerPort -sqlInstanceName $sqlInstanceName -PortNumber $PortNumber

# End of script
