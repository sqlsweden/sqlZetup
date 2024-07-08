# License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

# SQL Server Installation Script

## Overview

This repository contains a PowerShell script designed to install a SQL Server instance using either an ISO or EXE installer. The script automates several tasks, including:

- Checking if the script is run as an administrator.
- Ensuring the machine is part of a domain.
- Verifying if the specified SQL Server instance already exists.
- Prompting the user for necessary passwords.
- Calculating the number of TEMPDB files based on the number of CPU cores.
- Determining the installer path based on the provided ISO or EXE file.
- Executing the SQL Server installation with specified parameters.
- Verifying the installation and checking for logs in case of errors.

## Features

- Supports both ISO and EXE installers for SQL Server.
- Automatically calculates optimal TEMPDB configuration based on CPU cores.
- Provides detailed progress messages and error handling.
- Ensures script is run in a domain-connected environment with administrative privileges.

## Prerequisites

- PowerShell 5.0 or later.
- Administrative privileges on the machine where the script is run.
- The machine must be part of a domain.
- Valid SQL Server installer (ISO or EXE).

## Parameters

- `sqlInstanceName`: The name of the SQL Server instance to be installed (e.g., "MSSQLSERVER" for the default instance, "MYINSTANCE" for a named instance).
- `serviceDomainAccount`: The domain account for the SQL Server service.
- `sqlInstallerLocalPath`: The local path to the SQL Server installer ISO or EXE file.
- `SQLSYSADMINACCOUNTS`: The domain accounts to be added as SQL Server system administrators.

## Usage

1. Clone the repository to your local machine.
2. Open PowerShell with administrative privileges.
3. Navigate to the directory containing the script.
4. Execute the script with the required parameters.

### Example

```powershell
.\Install-SQLServer.ps1 -sqlInstanceName "SQL2019_9" -serviceDomainAccount "agdemo\SQLEngine" -sqlInstallerLocalPath "C:\Temp\SQLServerSetup.iso" -SQLSYSADMINACCOUNTS "agdemo\sqlgroup"
```
