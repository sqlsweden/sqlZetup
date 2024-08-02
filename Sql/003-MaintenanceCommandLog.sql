/*
    View Name: dbo.MaintenanceCommandLog
    Description: This view provides detailed information from the CommandLog table, including command execution details, error information, and performance metrics such as duration and fragmentation.
*/

CREATE VIEW dbo.MaintenanceCommandLog AS
SELECT  
    [ID],
    [DatabaseName],
    [SchemaName],
    [ObjectName],
    [ObjectType],
    [IndexName],
    [IndexType],
    [StatisticsName],
    [PartitionNumber],
    [ExtendedInfo],
    [Command],
    [CommandType],
    [StartTime],
    [EndTime],
    [ErrorNumber],
    [ErrorMessage],
    DATEDIFF(SECOND, StartTime, EndTime) AS [DurationInSeconds],
    ExtendedInfo.value('(/ExtendedInfo/PageCount)[1]', 'bigint') AS [PageCount],
    ExtendedInfo.value('(/ExtendedInfo/Fragmentation)[1]', 'numeric(7,5)') AS [Fragmentation]
FROM    
    [dbo].[CommandLog];
GO
