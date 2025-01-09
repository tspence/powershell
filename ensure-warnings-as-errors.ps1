# Run this script with arg[0] = the folder where you want to search for csproj files
$folderspec = $args[0]
$key = $args[1]
$value = $args[2]

# Review all files in this folder and child folders
if (Test-Path -Path $folderspec) {
    foreach ($path in Get-ChildItem -Recurse "${folderspec}/**/*.csproj") {

        # Load XML using "preserve whitespace" so we can avoid unnecessary github changes
        $xml = [xml]::new()
        $xml.PreserveWhitespace = $true
        $xml.Load($path)

        # We can only proceed if there's a single property group within the csproj file
        $propertyGroups = $xml.SelectNodes("//Project/PropertyGroup")
        if ($propertyGroups.Count -ne 1) {
            Write-Output "There are $($propertyGroups.Count) property groups in the file '${path}'; cannot edit"
        } else {

            # Look for that property within this property group
            $node = $propertyGroups[0].SelectSingleNode($key)
            if ($node) {
                Write-Output "The file '${path}' has project property group ${key} set to '${value}'"
            } else {
                Write-Output "File [${path}]: Setting project property group ${key} to '${value}'"

                # Construct the node with indentation before it, and a newline after it, so it looks appealing within the overall csproj file
                $newNodeText = "  <" + $key + ">" + $value + "</" + $key + ">`n  "
                $newNode = $xml.CreateDocumentFragment()
                $newNode.InnerXml = $newNodeText
                # We must save the results of this method call to a variable; otherwise it prints the function result to the console which looks ugly
                $newChild = $xml.Project.PropertyGroup.AppendChild($newNode)
                $xml.Save($path)
            }
        }
    }
} else {
    Write-Output "The folder ${folderspec} doesn't exist."
}
