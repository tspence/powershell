# Run this script with arg[0] = the folder where you want to search for csproj files
$folderspec = $args[0]
$key = $args[1]
$value = $args[2]

# Review all files in this folder and child folders
if (Test-Path -Path $folderspec) {
    foreach ($path in Get-ChildItem -Recurse "${folderspec}/**/*.csproj") {
        $xml = [xml]::new()
        $xml.PreserveWhitespace = $true
        $xml.Load($path)
        $node = $xml | Select-Xml -XPath "//Project/PropertyGroup/${key}"
        if ($node) {
            Write-Output "The file '${path}' has project property group ${key} set to '${value}'"
        } else {
            Write-Output "File [${path}]: Setting project property group ${key} to '${value}'"

            # Construct the node with indentation before it, and a newline after it, so it looks appealing within the overall csproj file
            $newNodeText = "  <" + $key + ">" + $value + "</" + $key + ">`n  "
            Write-Output "1"
            $newNode = $xml.CreateDocumentFragment()
            Write-Output "2"
            $newNode.InnerXml = $newNodeText
            Write-Output "3"
            $newChild = $xml.Project.PropertyGroup.AppendChild($newNode)
            Write-Output "4"
            $xml.Save($path)
            Write-Output "5"
        }
    }
} else {
    Write-Output "The folder ${folderspec} doesn't exist."
}
