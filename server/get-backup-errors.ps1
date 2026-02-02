# get previous backup errors

# 1 = backup started
# 4 = backup completed successfully
# 14 = backup completed successfully
Get-WinEvent -LogName "Microsoft-Windows-Backup" `
| Where-Object { $_.Id -ne 14 -and $_.Id -ne 1 -and $_.Id -ne 4 } `
| Sort-Object timecreated
