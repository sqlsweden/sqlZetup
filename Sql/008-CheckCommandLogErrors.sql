/*
    Stored Procedure: dbo.CheckCommandLogErrors
    Description: This stored procedure identifies potential errors or issues in the CommandLog table, such as:
                 - Null values in mandatory columns (Command, CommandType, StartTime).
                 - Inconsistent StartTime and EndTime values.
                 - Error messages without corresponding ErrorNumbers and vice versa.
                 It allows filtering by a date range and sorting by specified columns and directions.

    Parameters:
    @StartDate datetime2(7) = NULL: The start date for filtering log entries. If NULL, defaults to '1900-01-01T00:00:00'.
    @EndDate datetime2(7) = NULL: The end date for filtering log entries. If NULL, defaults to '9999-12-31T23:59:59'.
    @SortColumn nvarchar(60) = 'ID': The column to sort the results by. Default is 'ID'.
    @SortDirection nvarchar(4) = 'ASC': The direction to sort the results ('ASC' or 'DESC'). Default is 'ASC'.

    Usage Examples:
    -- With start and end dates
    EXEC dbo.CheckCommandLogErrors 
        @StartDate = '2024-01-01T00:00:00',
        @EndDate = '2024-01-31T23:59:59',
        @SortColumn = 'StartTime',
        @SortDirection = 'DESC';

    -- Without start and end dates
    EXEC dbo.CheckCommandLogErrors 
        @SortColumn = 'StartTime',
        @SortDirection = 'DESC';
*/

CREATE PROCEDURE dbo.CheckCommandLogErrors
    @StartDate datetime2(7) = NULL,
    @EndDate datetime2(7) = NULL,
    @SortColumn nvarchar(60) = 'ID',
    @SortDirection nvarchar(4) = 'ASC'
AS
BEGIN
    -- Use default dates if @StartDate and @EndDate are NULL
    IF @StartDate IS NULL
        SET @StartDate = '1900-01-01T00:00:00';
    IF @EndDate IS NULL
        SET @EndDate = '9999-12-31T23:59:59';

    DECLARE @SQL nvarchar(max);

    SET @SQL = '
    SELECT * FROM (
        -- Null values in mandatory columns
        SELECT ''Null Value in Command'' AS ErrorType, ID, DatabaseName, SchemaName, ObjectName, StartTime, EndTime, CommandType
        FROM dbo.CommandLog
        WHERE Command IS NULL
            AND StartTime BETWEEN @StartDate AND @EndDate
        UNION
        SELECT ''Null Value in CommandType'' AS ErrorType, ID, DatabaseName, SchemaName, ObjectName, StartTime, EndTime, CommandType
        FROM dbo.CommandLog
        WHERE CommandType IS NULL
            AND StartTime BETWEEN @StartDate AND @EndDate
        UNION
        SELECT ''Null Value in StartTime'' AS ErrorType, ID, DatabaseName, SchemaName, ObjectName, StartTime, EndTime, CommandType
        FROM dbo.CommandLog
        WHERE StartTime IS NULL
            AND StartTime BETWEEN @StartDate AND @EndDate
        UNION
        -- Inconsistent StartTime and EndTime
        SELECT ''Inconsistent StartTime and EndTime'' AS ErrorType, ID, DatabaseName, SchemaName, ObjectName, StartTime, EndTime, CommandType
        FROM dbo.CommandLog
        WHERE EndTime < StartTime
            AND StartTime BETWEEN @StartDate AND @EndDate
        UNION
        -- Error messages with ErrorNumber
        SELECT ''ErrorMessage present without ErrorNumber'' AS ErrorType, ID, DatabaseName, SchemaName, ObjectName, StartTime, EndTime, CommandType
        FROM dbo.CommandLog
        WHERE ErrorMessage IS NOT NULL 
            AND ErrorNumber IS NULL
            AND StartTime BETWEEN @StartDate AND @EndDate
        UNION
        SELECT ''ErrorNumber present without ErrorMessage'' AS ErrorType, ID, DatabaseName, SchemaName, ObjectName, StartTime, EndTime, CommandType
        FROM dbo.CommandLog
        WHERE ErrorNumber IS NOT NULL 
            AND ErrorMessage IS NULL
            AND StartTime BETWEEN @StartDate AND @EndDate
    ) AS Errors
    ORDER BY ' + @SortColumn + ' ' + @SortDirection;

    EXEC sp_executesql @SQL, N'@StartDate datetime2(7), @EndDate datetime2(7)', @StartDate, @EndDate;
END
GO
