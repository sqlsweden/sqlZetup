# SQLZetup

## Overview

**´Install-SQLZetup´** is a PowerShell function that automates the installation and configuration of SQL Server, including additional setup tasks and optional SQL Server Management Studio (SSMS) installation. This script streamlines the installation and configuration process, ensuring adherence to best practices and optimizing SQL Server configurations for performance.

## Key Features

- **Automated Installation:** Mounts the SQL Server ISO and retrieves the setup executable, installs SQL Server with specified configurations, and ensures the SQL Server Agent is running.

- **Configuration:** Configures TempDB settings, error log settings, and other SQL Server parameters.

- **Script Execution:** Executes a series of SQL scripts in a specified order.

- **SSMS Installation:** Checks for and optionally installs SQL Server Management Studio (SSMS).

- **Updates:** Applies necessary updates to SQL Server.

- **Flexibility:** Utilizes relative paths for flexibility in script and directory locations, and provides secure prompts for sensitive information such as passwords.

- **Volume Checks:** Ensures volume block sizes are optimized for SQL Server.

## Supported SQL Server Versions

- 2016

- 2017

- 2019

- 2022

## Supported Editions

- Developer (for test and development)

- Standard

- Enterprise

## Parameters

- **´SqlZetupRoot´** (Mandatory): Path to the root directory containing the SQL Server ISO, SSMS installer, and setup scripts.

- **´IsoFileName´:** Name of the SQL Server ISO file.

- **´SsmsInstallerFileName´** (Mandatory): Name of the SSMS installer file. Default is "SSMS-Setup-ENU.exe".

- **´Version´** (Mandatory): The version of SQL Server to install (e.g., 2016, 2017, 2019, 2022). Default is 2022.

- **´Edition´** (Mandatory): The edition of SQL Server to install (e.g., Developer, Standard, Enterprise).

- **´ProductKey´:** The product key for SQL Server installation. Required for Standard and Enterprise editions.

- **´Collation´** (Mandatory): The collation settings for SQL Server. Default is "Finnish_Swedish_CI_AS".

- **´SqlSvcAccount´** (Mandatory): The service account for SQL Server.

- **´AgtSvcAccount** (Mandatory): The service account for SQL Server Agent.

- **´AdminAccount´** (Mandatory): The administrator account for SQL Server.

- **´SqlDataDir´** (Mandatory): The directory for SQL Server data files. Default is "E:\MSSQL\Data".

- **´SqlLogDir´** (Mandatory): The directory for SQL Server log files. Default is "F:\MSSQL\Log".

- **´SqlBackupDir´** (Mandatory): The directory for SQL Server backup files. Default is "H:\MSSQL\Backup".

- **´SqlTempDbDir´** (Mandatory): The directory for SQL Server TempDB files. Default is "G:\MSSQL\Data".

- **´TempdbDataFileSize´** (Mandatory): The size of the TempDB data file in MB. Default is 512.

- **´TempdbDataFileGrowth´** (Mandatory): The growth size of the TempDB data file in MB. Default is 64.

- **´TempdbLogFileSize´:** The size of the TempDB log file in MB. Default is 64.

- **´TempdbLogFileGrowth´** (Mandatory): The growth size of the TempDB log file in MB. Default is 64.

- **´Port´**(Mandatory): The port for SQL Server. Default is 1433.

- **´InstallSsms´** (Mandatory): Indicates whether to install SQL Server Management Studio. Default is $true.

- **´DebugMode´** (Mandatory): Enables debug mode for detailed logging. Default is **$false**.

## Example

```powershell
Install-SQLZetup -SqlZetupRoot "C:\Temp\sqlZetup" -IsoFileName "SQLServer2022-x64-ENU-Dev.iso" -SsmsInstallerFileName "SSMS-Setup-ENU.exe" -Version 2022 -Edition "Developer" -Collation "Finnish_Swedish_CI_AS" -SqlSvcAccount "agdemo\sqlengine" -AgtSvcAccount "agdemo\sqlagent" -AdminAccount "agdemo\sqlgroup" -SqlDataDir "E:\MSSQL\Data" -SqlLogDir "F:\MSSQL\Log" -SqlBackupDir "H:\MSSQL\Backup" -SqlTempDbDir "G:\MSSQL\Data" -TempdbDataFileSize 512 -TempdbDataFileGrowth 64 -TempdbLogFileSize 64 -TempdbLogFileGrowth 64 -Port 1433 -InstallSsms $true -DebugMode $false
```

## Notes

- **Author:** Michael Pettersson, Cegal

- **Version:** 1.0

- **License:** MIT License

## License

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.

### 🚧 Under Development 🚧

This project is currently in development. It is not yet a fully functional solution and may not work as expected. Please do not use this in a production environment until it has reached a stable release.
