# Run this script with arg[0] = the file spec and arg[1] = the Azure Devops Feature to group all tasks 
$filespec = $args[0]
$parentFeature = $args[1]
$project = "MyProject"
$type = "User Story"
$organization = "https://dev.azure.com/MyOrganization"

# Create one task for each file in this folder
foreach ($path in Get-ChildItem $filespec) {
  $file = [System.IO.Path]::GetFileNameWithoutExtension($path)
  $title = "Add string length validation to $file"
  $description = "<div>Story:</div>" +
    "<div><ul>" +
    "<li>As a developer working with My Project</li>" +
    "<li>I would like to add string length validation to $file ($path)</li>" +
    "<li>So that I get an error when my string is too long.</li>" +
    "</ul></div>"
  $resultJson = az boards work-item create --project $project --title $title --type $type --description $description --organization $organization
  $result = $resultJson | ConvertFrom-Json
  $id = $result.id
  $result2 = az boards work-item relation add --id $id --relation-type parent --target-id $parentFeature
  Write-Output "Created ticket $($title)..."
}