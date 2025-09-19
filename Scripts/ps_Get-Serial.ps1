
# Get the serialnumber of the machine via the CIMinstance cmdlet
$serial = (Get-CimInstance Win32_BIOS).SerialNumber

# Format the serialnumber to give back the last 4 characters prefixed with 'PC-'
return 'PC-{0}' -f $serial.Substring($serial.Length - 4)
