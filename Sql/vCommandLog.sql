CREATE VIEW [dbo].[vCommandLog]
AS
    SELECT  [ID] ,
            [DatabaseName] ,
            [SchemaName] ,
            [ObjectName] ,
            [ObjectType] ,
            [IndexName] ,
            [IndexType] ,
            [StatisticsName] ,
            [PartitionNumber] ,
            [ExtendedInfo] ,
            [Command] ,
            [CommandType] ,
            [StartTime] ,
            [EndTime] ,
            [ErrorNumber] ,
            [ErrorMessage] ,
            DATEDIFF(SECOND, StartTime, EndTime) [DurationInSeconds] ,
            ExtendedInfo.value('(/ExtendedInfo/PageCount)[1]', 'bigint') AS [pagecount] ,
            ExtendedInfo.value('(/ExtendedInfo/Fragmentation)[1]',
                               'numeric(7,5)') AS [Fragmentation]
    FROM    [dbo].[CommandLog]; 
GO