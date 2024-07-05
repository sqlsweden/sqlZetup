<#
.SYNOPSIS
    Script to install SQL Server instance using either an ISO or EXE installer.

.DESCRIPTION
    This script performs the following actions:
    - Checks if the script is being run as an administrator.
    - Ensures the machine is part of a domain.
    - Checks if the specified SQL Server instance already exists.
    - Prompts the user for required passwords.
    - Calculates the number of TEMPDB files based on the number of CPU cores.
    - Determines the installer path based on the provided ISO or EXE file.
    - Executes the SQL Server installation with specified parameters.
    - Verifies the installation and checks for logs in case of errors.

.PARAMETER sqlInstanceName
    The name of the SQL Server instance to be installed (e.g., "MSSQLSERVER" for default instance, "MYINSTANCE" for named instance).

.PARAMETER serviceDomainAccount
    The domain account for the SQL Server service.

.PARAMETER sqlInstallerLocalPath
    The local path to the SQL Server installer ISO or EXE file.

.PARAMETER SQLSYSADMINACCOUNTS
    The domain accounts to be added as SQL Server system administrators.

.PARAMETER DebugMode
    Enables detailed logging and verbose output for debugging purposes.

.NOTES
    - This script must be run as an administrator.
    - This script only supports machines that are part of a domain.
    - Ensure the provided SQL Server installer path is valid and accessible.
    - Adjust the script parameters as necessary for your environment.

.EXAMPLE
    .\Install-SQLServer.ps1 -sqlInstanceName "SQL2019_9" -serviceDomainAccount "agdemo\SQLEngine" -sqlInstallerLocalPath "C:\Temp\SQLServerSetup.iso" -SQLSYSADMINACCOUNTS "agdemo\sqlgroup" -DebugMode $true

    This example installs a SQL Server instance named "SQL2019_9" using the specified domain account and ISO file, adds the specified sysadmin accounts, and enables debugging mode.
#>

# Configurable parameters
param(
    [string]$sqlInstanceName = "SQL2019_6", # Set the SQL Server instance name
    [string]$serviceDomainAccount = "agdemo\SQLEngine", # Set the domain account for SQL Server service
    [string]$sqlInstallerLocalPath = "C:\Temp\SQLServerSetup.iso", # Set the local path to the SQL Server installer ISO or EXE
    [string]$SQLSYSADMINACCOUNTS = "agdemo\sqlgroup", # Set the domain accounts to be added as sysadmins
    [switch]$DebugMode = $False # Enable debugging mode
)

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
    $logPath = "C:\Program Files\Microsoft SQL Server\150\Setup Bootstrap\Log"
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
    "SQLTEMPDBDIR"                  = "C:\tempdbdata"
    "SQLTEMPDBLOGDIR"               = "C:\tempdblog"
    "SQLTEMPDBFILESIZE"             = "64"
    "SQLTEMPDBLOGFILESIZE"          = "64"
    "SQLUSERDBDIR"                  = "C:\userdbdata"
    "SQLUSERDBLOGDIR"               = "C:\userdblog"
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

# End of script
