# used to pull computer onto a csv for auditing using the lastlogondate field with in AD

$computers = get-adcomputer -filter {
    enabled -eq $true 
    -and operatingsystem -like 'Windows 1*' 
    -and lastlogondate -lt $date 
} -properties * 

$computers | sort-object lastlogondate | select-object name,operatingsystem,lastlogondate