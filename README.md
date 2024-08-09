# SQLZetup

## Overview

**´Install-SQLZetup´** is a PowerShell function that automates the installation and configuration of SQL Server, including additional setup tasks and optional SQL Server Management Studio (SSMS) installation. This script streamlines the installation and configuration process, ensuring adherence to best practices and optimizing SQL Server configurations for performance.

## Key Features

- **Automated Installation:** Mounts the SQL Server ISO and retrieves the setup executable, installs SQL Server with specified configuration.

- **Configuration:** Performs a complete configuration of SQL Server that covers all aspects concerning performance, availability, and security.

- **Script Execution:** Executes a series of SQL scripts in a specified order that includes, amongst other things, creating a DBA database and setting up and scheduling Ola Hallengren's Maintenance Solution for SQL Server.

- **SSMS Installation:** Checks for and optionally installs SQL Server Management Studio (SSMS).

- **Updates:** Applies necessary updates to SQL Server when available after manual upload.

- **Flexibility:** Utilizes relative paths for flexibility in script and directory locations, and provides secure prompts for sensitive information such as passwords.

- **Volume Checks:** Ensures volume block sizes are optimized for SQL Server.

[Return to top](#sqlzetup)

## Supported SQL Server Versions

- 2016

- 2017

- 2019

- 2022

[Return to top](#sqlzetup)

## Supported Editions

- Developer (for test and development)

- Standard

- Enterprise

[Return to top](#sqlzetup)

## Installation

To install the solution, follow the steps below:

1. Download the latest release from the [GitHub Releases](https://github.com/sqlsweden/SQLZetup/releases) page. Make sure to include `dbatools` if needed.
2. Upload the downloaded files to the target machine and extract the `.zip` file. You can extract it to a directory such as `C:\Temp`.
3. Place the installation media files, such as `SQLServer2022-x64-ENU-Dev.iso` and `SSMS-Setup-ENU.exe`, in the appropriate directories as shown below.
4. **SQL Server updates** and SSMS can be downloaded from [https://sqlserverupdates.com/](https://sqlserverupdates.com/). Once downloaded, updates should be manually placed in the correct directory under `Updates`, as shown below. For example, `SQLServer2022-KB5036432-x64.exe` should be placed in the `2022/` folder.

Here is an example of the directory structure after extraction and placement of required files:

```markdown
sqlzetup/
├── Doc/
├── Monitoring/
├── Sql/
├── Updates/
│   ├── 2016/
│   ├── 2017/
│   ├── 2019/
│   ├── 2022/
│   └── SQLServer2022-KB5036432-x64.exe
├── .gitattributes
├── .gitignore
├── Install-SQLZetup.ps1
├── LICENSE.txt
├── README.md
├── SQLServer2022-x64-ENU-Dev.iso
└── SSMS-Setup-ENU.exe
```

[Return to top](#sqlzetup)

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

[Return to top](#sqlzetup)

## Example

```powershell
Install-SQLZetup -SqlZetupRoot "C:\Temp\sqlZetup" -IsoFileName "SQLServer2022-x64-ENU-Dev.iso" -SsmsInstallerFileName "SSMS-Setup-ENU.exe" -Version 2022 -Edition "Developer" -Collation "Finnish_Swedish_CI_AS" -SqlSvcAccount "agdemo\sqlengine" -AgtSvcAccount "agdemo\sqlagent" -AdminAccount "agdemo\sqlgroup" -SqlDataDir "E:\MSSQL\Data" -SqlLogDir "F:\MSSQL\Log" -SqlBackupDir "H:\MSSQL\Backup" -SqlTempDbDir "G:\MSSQL\Data" -TempdbDataFileSize 512 -TempdbDataFileGrowth 64 -TempdbLogFileSize 64 -TempdbLogFileGrowth 64 -Port 1433 -InstallSsms $true -DebugMode $false
```

[Return to top](#sqlzetup)

## Report Issues or Request Features

If you encounter any issues or have feature requests, please use the following options:

- **Report an issue**: Go to [Issues](https://github.com/sqlsweden/SQLZetup/issues) on GitHub to open a new issue.
- **Request new features**: Go to [Discussions](https://github.com/sqlsweden/SQLZetup/discussions) on GitHub to discuss new features or improvements.

Your feedback is valuable, and I appreciate your contributions!

[Return to top](#sqlzetup)

## Notes

- **Author:** Michael Pettersson, Cegal

- **Version:** 1.0.0

- **License:** MIT License

[Return to top](#sqlzetup)

## License

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.

[Return to top](#sqlzetup)
