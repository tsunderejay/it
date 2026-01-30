# this could be useful with gpo scripts or schedueled tasks
# burnt toast does a more complete module for it but w/e
Add-Type -AssemblyName System.Windows.Forms

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-Process -id $pid).Path)
$notify.BalloonTipTitle = "Testing an alert"
$notify.BalloonTipText = "..."
$notify.Visible = $true
$notify.ShowBalloonTip(5000)
