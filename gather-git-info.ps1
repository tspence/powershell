# Which JSON file are we targeting?
$filePath = $args[0]
if ($filePath -eq "") {
    $filePath = "appSettings.json"
}
Write-Output "Working with file '$($filePath)'"

# Gather git information
$gitInfoRaw = & git show --format=format:"%h%n%ci%n%d"
$items = $gitInfoRaw.Split([Environment]::NewLine)
Write-Output "Hash - $($items[0])"
Write-Output "Date - $($items[1])"
Write-Output "Branch - $($items[2])"

# Open a JSON file and insert these values at the designated location
$fileExists = Test-Path -PathType Leaf -Path $filePath
if ($fileExists) {
    $originalJson = Get-Content -Path $filePath | ConvertFrom-Json
    $newData = $originalJson
} else {
    Write-Output "File $($filePath) does not exist, creating."
    $newData = "{}" | ConvertFrom-Json
}
Add-Member -InputObject $newData -Name "Hash" -value $items[0] -MemberType NoteProperty -Force
Add-Member -InputObject $newData -Name "Date" -value $items[1] -MemberType NoteProperty -Force
Add-Member -InputObject $newData -Name "Branch" -value $items[2] -MemberType NoteProperty -Force
$newData | ConvertTo-Json | Out-File $filePath 
Write-Output "Contents of $($filePath) updated with latest git info."