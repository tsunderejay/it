# used to pull users onto a csv for auditing using the lastlogondate field with in AD

$users = get-aduser -filter {
    enabled -eq $true
    -and lastlogondate -lt $date
} -properties *

$users | sort-object lastlogondate | select-object name,displayname,lastlogondate
