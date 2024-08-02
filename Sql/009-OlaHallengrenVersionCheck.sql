/*
    View Name: dbo.OlaHallengrenVersionCheck
    Description: This view checks the version of Ola Hallengren's SQL Server Maintenance Solution scripts.
    It retrieves the schema name, object name, version, and checksum for specific maintenance objects.

    Version History:
    https://ola.hallengren.com/versions.html

    If you don't have the latest version, you can download and install the latest version:
    https://ola.hallengren.com/scripts/MaintenanceSolution.sql
*/

CREATE VIEW dbo.OlaHallengrenVersionCheck AS
SELECT 
    sch.[name] AS [Schema Name], 
    obj.[name] AS [Object Name],
    CASE 
        WHEN CHARINDEX(N'--// Version: ', OBJECT_DEFINITION(obj.[object_id])) > 0 
        THEN SUBSTRING(OBJECT_DEFINITION(obj.[object_id]), CHARINDEX(N'--// Version: ', OBJECT_DEFINITION(obj.[object_id])) + LEN(N'--// Version: ') + 1, 19) 
    END AS [Version],
    CAST(CHECKSUM(CAST(OBJECT_DEFINITION(obj.[object_id]) AS nvarchar(max)) COLLATE SQL_Latin1_General_CP1_CI_AS) AS bigint) AS [Checksum]
FROM 
    sys.objects AS obj
INNER JOIN 
    sys.schemas AS sch 
ON 
    obj.[schema_id] = sch.[schema_id]
WHERE 
    sch.[name] = N'dbo'
AND 
    obj.[name] IN (N'CommandExecute', N'DatabaseBackup', N'DatabaseIntegrityCheck', N'IndexOptimize');
