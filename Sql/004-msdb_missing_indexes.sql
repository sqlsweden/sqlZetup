/*
Creates a set of missing indexes for MSDB database              |
*/

-- Adding indexes to backupset table
CREATE NONCLUSTERED INDEX IX_backupset_media_set_id ON backupset (media_set_id);
CREATE NONCLUSTERED INDEX IX_backupset_backup_finish_date_media_set_id ON backupset (backup_finish_date) INCLUDE (media_set_id);
CREATE NONCLUSTERED INDEX IX_backupset_backup_start_date ON backupset (backup_start_date);

-- Adding indexes to backupfile table
CREATE NONCLUSTERED INDEX IX_backupfile_backup_set_id ON backupfile (backup_set_id);

-- Adding indexes to backupfilegroup table
CREATE NONCLUSTERED INDEX IX_backupfilegroup_backup_set_id ON backupfilegroup (backup_set_id);

-- Adding indexes to restorefile table
CREATE CLUSTERED INDEX IX_restorefile_restore_history_id ON restorefile (restore_history_id);

-- Adding indexes to restorefilegroup table
CREATE CLUSTERED INDEX IX_restorefilegroup_restore_history_id ON restorefilegroup (restore_history_id);

-- Adding indexes to backupmediafamily table
CREATE NONCLUSTERED INDEX IX_backupmediafamily_media_set_id ON backupmediafamily (media_set_id);
