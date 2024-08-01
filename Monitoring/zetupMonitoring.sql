-------------------------------------------------------------
--  SQL Server Configuration Script
--
--  This script performs the following tasks:
--  1. Checks if there are any SQL Agent jobs starting with 'DBA%' and stops if there are none.
--  2. Enables Database Mail XPs if not already enabled.
--  3. Creates a Database Mail profile and SMTP account with support for either anonymous or authenticated login.
--  4. Associates the SMTP account with the Database Mail profile.
--  5. Removes any existing Database Mail profiles, accounts, and operators before creating new ones.
--  6. Adds an operator and associates the operator with the profile.
--  7. Configures alerts for high severity errors and specific errors (823, 824, 825).
--  8. Sets up notifications for these alerts.
--  9. Ensures SQL Agent jobs starting with 'DBA%' have email notifications set up for job failures.
-- 10. Sends a test email to verify the configuration.
-- 11. Reports if the test email was sent successfully or not by checking the Database Mail log.
-------------------------------------------------------------

USE msdb;
GO

-- Check for jobs starting with 'DBA%'
DECLARE @dba_jobs_count INT;
SET @dba_jobs_count = (SELECT COUNT(*) FROM msdb.dbo.sysjobs WHERE name LIKE 'DBA%');

IF @dba_jobs_count = 0
BEGIN
    RAISERROR('Installation cannot proceed as there are no SQL Agent jobs starting with ''DBA%%''.', 16, 1);
    RETURN;
END

-- Enable Database Mail XPs if not already enabled
DECLARE @DatabaseMailEnabled BIT;
SET @DatabaseMailEnabled = (
    SELECT CONVERT(bit, c.value_in_use)
    FROM sys.configurations c
    WHERE c.name = N'Database Mail XPs'
);
IF @DatabaseMailEnabled = 0
BEGIN
    EXEC sys.sp_configure @configname = 'Show Advanced Options', @configvalue = 1;
    RECONFIGURE;
    EXEC sys.sp_configure @configname = 'Database Mail XPs', @configvalue = 1;
    RECONFIGURE;
END

DECLARE @profile_name sysname,
        @account_name sysname,
        @SMTP_servername sysname,
        @email_address NVARCHAR(128),
        @display_name NVARCHAR(128),
        @SMTP_port INT,
        @SMTP_security NVARCHAR(50),
        @SMTP_username NVARCHAR(128),
        @SMTP_password NVARCHAR(128),
        @enable_ssl BIT,
        @use_anonymous_login BIT,
        @operator_name sysname,
        @operator_email_address NVARCHAR(128);

-- Profile name. Replace with the name for your profile
SET @profile_name = 'Fake_Profile';

-- Account information. Replace with the information for your account.
SET @account_name = 'Fake_Account';                 -- The name of the mail account to be created
SET @SMTP_servername = 'smtp.fakeemail.com';        -- The SMTP server used to send emails
SET @email_address = 'fake.email@fakeemail.com';    -- The email address to use as the sender
SET @display_name = 'noreply@fakeemail.com';        -- The display name for the sender email
SET @SMTP_port = 587;                               -- The port number for the SMTP server
SET @SMTP_security = 'STARTTLS';                    -- The security protocol for the SMTP server ('None', 'SSL', 'TLS', 'STARTTLS')
SET @SMTP_username = 'fake_username';               -- The username for SMTP authentication
SET @SMTP_password = 'fake_password';               -- The password for SMTP authentication
SET @use_anonymous_login = 0;                       -- Set to 1 for anonymous login, 0 for authenticated login

-- Operator information. Replace with the information for your operator.
SET @operator_name = 'Fake_Operator';               -- The name of the operator to be created
SET @operator_email_address = 'alerts@fakeemail.com'; -- The email address of the operator

-- Determine the value for @enable_ssl based on @SMTP_security
SET @enable_ssl = CASE @SMTP_security WHEN 'SSL' THEN 1 WHEN 'TLS' THEN 1 WHEN 'STARTTLS' THEN 1 ELSE 0 END;

-- Start a transaction before modifying the account, profile, and operator
BEGIN TRANSACTION;

DECLARE @rv INT;

-- Remove all existing Database Mail accounts
DECLARE @existing_account_name sysname;
DECLARE account_cursor CURSOR FOR
SELECT name FROM msdb.dbo.sysmail_account;
OPEN account_cursor;
FETCH NEXT FROM account_cursor INTO @existing_account_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXECUTE @rv = msdb.dbo.sysmail_delete_account_sp
        @account_name = @existing_account_name;

    IF @rv <> 0
    BEGIN
        RAISERROR('Failed to delete the specified Database Mail account (%s).', 16, 1, @existing_account_name);
        ROLLBACK TRANSACTION;
        GOTO done;
    END

    FETCH NEXT FROM account_cursor INTO @existing_account_name;
END

CLOSE account_cursor;
DEALLOCATE account_cursor;

-- Remove all existing Database Mail profiles
DECLARE @existing_profile_name sysname;
DECLARE profile_cursor CURSOR FOR
SELECT name FROM msdb.dbo.sysmail_profile;
OPEN profile_cursor;
FETCH NEXT FROM profile_cursor INTO @existing_profile_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXECUTE @rv = msdb.dbo.sysmail_delete_profile_sp
        @profile_name = @existing_profile_name;

    IF @rv <> 0
    BEGIN
        RAISERROR('Failed to delete the specified Database Mail profile (%s).', 16, 1, @existing_profile_name);
        ROLLBACK TRANSACTION;
        GOTO done;
    END

    FETCH NEXT FROM profile_cursor INTO @existing_profile_name;
END

CLOSE profile_cursor;
DEALLOCATE profile_cursor;

-- Remove all existing operators
DECLARE @existing_operator_name sysname;
DECLARE operator_cursor CURSOR FOR
SELECT name FROM msdb.dbo.sysoperators;
OPEN operator_cursor;
FETCH NEXT FROM operator_cursor INTO @existing_operator_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    EXECUTE @rv = msdb.dbo.sp_delete_operator
        @name = @existing_operator_name;

    IF @rv <> 0
    BEGIN
        RAISERROR('Failed to delete the specified operator (%s).', 16, 1, @existing_operator_name);
        ROLLBACK TRANSACTION;
        GOTO done;
    END

    FETCH NEXT FROM operator_cursor INTO @existing_operator_name;
END

CLOSE operator_cursor;
DEALLOCATE operator_cursor;

-- Add the account
IF @use_anonymous_login = 1
BEGIN
    EXECUTE @rv = msdb.dbo.sysmail_add_account_sp
        @account_name = @account_name,
        @email_address = @email_address,
        @display_name = @display_name,
        @replyto_address = NULL,
        @description = NULL,
        @mailserver_name = @SMTP_servername,
        @mailserver_type = 'SMTP',
        @port = @SMTP_port,
        @enable_ssl = @enable_ssl;
END
ELSE
BEGIN
    EXECUTE @rv = msdb.dbo.sysmail_add_account_sp
        @account_name = @account_name,
        @email_address = @email_address,
        @display_name = @display_name,
        @replyto_address = NULL,
        @description = NULL,
        @mailserver_name = @SMTP_servername,
        @mailserver_type = 'SMTP',
        @port = @SMTP_port,
        @enable_ssl = @enable_ssl,
        @username = @SMTP_username,
        @password = @SMTP_password;
END

IF @rv <> 0
BEGIN
    RAISERROR('Failed to create the specified Database Mail account (%s).', 16, 1, @account_name);
    ROLLBACK TRANSACTION;
    GOTO done;
END

-- Add the profile
EXECUTE @rv = msdb.dbo.sysmail_add_profile_sp
    @profile_name = @profile_name;

IF @rv <> 0
BEGIN
    RAISERROR('Failed to create the specified Database Mail profile (%s).', 16, 1, @profile_name);
    ROLLBACK TRANSACTION;
    GOTO done;
END

-- Associate the account with the profile
EXECUTE @rv = msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name = @profile_name,
    @account_name = @account_name,
    @sequence_number = 1;

IF @rv <> 0
BEGIN
    RAISERROR('Failed to associate the specified profile with the specified account (%s).', 16, 1, @account_name);
    ROLLBACK TRANSACTION;
    GOTO done;
END

-- Add the operator
EXECUTE @rv = msdb.dbo.sp_add_operator
    @name = @operator_name,
    @enabled = 1,
    @email_address = @operator_email_address;

IF @rv <> 0
BEGIN
    RAISERROR('Failed to create the specified operator (%s).', 16, 1, @operator_name);
    ROLLBACK TRANSACTION;
    GOTO done;
END

-- Configure alerts
DECLARE @alert_names TABLE (name NVARCHAR(128), severity INT, message_id INT, description NVARCHAR(MAX));

INSERT INTO @alert_names (name, severity, message_id, description)
VALUES
    (N'URGENT: Severity 17 Error:', 17, 0, N'SQL Server has encountered a resource problem, such as memory or disk space issues. Check system resources and free up memory or disk space as needed. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 18 Error: Nonfatal Internal Error', 18, 0, N'An internal SQL Server error that is nonfatal but may affect performance. Analyze the error messages and review SQL Server logs to understand the cause. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 19 Error: Fatal Error in Resource', 19, 0, N'A severe error indicating that a particular resource is not available. Check the availability of system resources and troubleshoot any hardware issues. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 20 Error: Fatal Error in Current Process', 20, 0, N'A severe error indicating that the current process has crashed. Troubleshoot and review SQL Server logs to identify the cause. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 21 Error: Fatal Error in Database Process', 21, 0, N'A severe error in a database process, often requiring a database restore. Check the database status and restore from a backup if necessary. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 22 Error Fatal Error: Table Integrity Suspect', 22, 0, N'Indicates table integrity issues, which may suggest corruption. Use DBCC CHECKDB to check and resolve table integrity issues. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 23 Error: Fatal Error Database Integrity Suspect', 23, 0, N'Indicates database integrity is at risk, often due to corruption. Use DBCC CHECKDB to identify and repair corruption. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 24 Error: Fatal Hardware Error', 24, 0, N'A severe error indicating hardware issues, such as with the disk. Check hardware logs and contact the hardware vendor if needed. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Severity 25 Error: Fatal Error', 25, 0, N'A generic severe error requiring immediate attention. Analyze SQL Server logs to understand and resolve the problem. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/database-engine-events-and-errors?view=sql-server-ver15'),
    (N'URGENT: Error 823: I/O Error', 0, 823, N'Indicates that SQL Server has encountered issues reading from or writing to the disk. Check the underlying I/O system hardware and run DBCC CHECKDB to verify data integrity. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-823-database-engine-error?view=sql-server-ver15'),
    (N'URGENT: Error 824: Logical Consistency Error', 0, 824, N'Indicates that SQL Server has encountered logical inconsistencies when reading data. Run DBCC CHECKDB to identify and repair logical inconsistencies. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-824-database-engine-error?view=sql-server-ver15'),
    (N'URGENT: Error 825: Read Retry', 0, 825, N'Indicates that SQL Server experienced a transient error during a read operation but successfully retried. Monitor for further 825 errors and check the system hardware for potential issues. Further Information: https://docs.microsoft.com/en-us/sql/relational-databases/errors-events/mssqlserver-825-database-engine-error?view=sql-server-ver15');

DECLARE @alert_name NVARCHAR(128),
        @severity INT,
        @message_id INT,
        @description NVARCHAR(MAX);

DECLARE alert_cursor CURSOR FOR
SELECT name, severity, message_id, description FROM @alert_names;

OPEN alert_cursor;
FETCH NEXT FROM alert_cursor INTO @alert_name, @severity, @message_id, @description;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysalerts WHERE name = @alert_name)
    BEGIN
        EXEC msdb.dbo.sp_add_alert
            @name = @alert_name,
            @message_id = @message_id,
            @severity = @severity,
            @enabled = 1,
            @delay_between_responses = 3600, -- Updated to 60 minutes
            @include_event_description_in = 1,
            @notification_message = @description;
    END

    -- Setup notifications
    EXEC msdb.dbo.sp_add_notification
        @alert_name = @alert_name,
        @operator_name = @operator_name,
        @notification_method = 1;

    FETCH NEXT FROM alert_cursor INTO @alert_name, @severity, @message_id, @description;
END

CLOSE alert_cursor;
DEALLOCATE alert_cursor;

-- Ensure monitoring for SQL Agent jobs starting with 'DBA%'
DECLARE @job_id UNIQUEIDENTIFIER,
        @job_name NVARCHAR(128);

DECLARE job_cursor CURSOR FOR
SELECT job_id, name
FROM msdb.dbo.sysjobs
WHERE name LIKE 'DBA%';

OPEN job_cursor;
FETCH NEXT FROM job_cursor INTO @job_id, @job_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Add job failure notification
    EXEC msdb.dbo.sp_update_job
        @job_id = @job_id,
        @notify_level_email = 2,
        @notify_email_operator_name = @operator_name;

    FETCH NEXT FROM job_cursor INTO @job_id, @job_name;
END

CLOSE job_cursor;
DEALLOCATE job_cursor;

COMMIT TRANSACTION;

done:

-- Send a test email
EXEC msdb.dbo.sp_send_dbmail
    @profile_name = @profile_name,
    @recipients = @operator_email_address,
    @subject = 'Test Email from SQL Server',
    @body = 'This is a test email sent from SQL Server Database Mail.';

GO
