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

        # What does this look like?
        # # Function to recursively traverse and print nodes
        # function Get-XmlNodes($node) {
        #     if ($node.GetType().FullName -eq "System.Xml.XmlWhitespace") {
        #         Write-Host "Whitespace: '$($node.OuterXml)'"
        #     }
        #     foreach ($child in $node.ChildNodes) {
        #         Get-XmlNodes $child
        #     }
        # }

        # # Start with the root node
        # Get-XmlNodes $xml.DocumentElement

        # We can only proceed if there's a single property group within the csproj file
        $propertyGroups = $xml.SelectNodes("//Project/PropertyGroup")
        if ($propertyGroups.Count -ne 1) {
            Write-Output "There are $($propertyGroups.Count) property groups in the file '${path}'; cannot edit"
        } else {

            # Try to figure out the maximum indentation level of children beneath this node, guessing 4 as default
            $spacesBeforeElement = 4
            foreach ($whitespace in $propertyGroups[0].ChildNodes) {
                if ($whitespace.GetType().FullName -eq "System.Xml.XmlWhitespace") {
                    $str = $whitespace.OuterXml.ToString()
                    $spaces = 0
                    foreach ($char in $str.ToCharArray()) {
                        if ($char -eq " ") {
                            $spaces = $spaces + 1
                        }
                    }
                    if ($spacesBeforeElement -lt $spaces) {
                        $spacesBeforeElement = $spaces
                    }
                }
            }

            # We are at level two: Project is at the root, PropertyGroup is at level one, and the new item we're adding is at level two
            # So we want to determine the number-of-spaces by dividing spacesBeforeElement by two
            $spacesBeforeElement = $spacesBeforeElement / 2
            $indentation = [string]::new(' ', $spacesBeforeElement)

            # Look for that property within this property group
            $node = $propertyGroups[0].SelectSingleNode($key)
            if ($node) {
                Write-Output "The file '${path}' has project property group ${key} set to '${value}'"
            } else {
                Write-Output "File [${path}]: Setting project property group ${key} to '${value}'"

                # Preserve original file contents in case warnings-as-errors breaks this build
                # $original = Get-Content $path

                # Construct the node with indentation before it, and a newline after it, so it looks appealing within the overall csproj file
                # Note that we don't need a newline beforehand, for some reason the preserve whitespace option would cause it to be a duplicate
                # Note that the previous whitespace element would already have indented us once
                # Also note that we want to use `r`n since we are running on Windows to avoid changing line endings for the file
                $newNodeText = "${indentation}<" + $key + ">" + $value + "</" + $key + ">`r`n${indentation}"
                $newNode = $xml.CreateDocumentFragment()
                $newNode.InnerXml = $newNodeText
                # We must save the results of this method call to a variable; otherwise it prints the function result to the console which looks ugly
                $_ = $xml.Project.PropertyGroup.AppendChild($newNode)
                $xml.Save($path)

                # Attempt to build the modified project
                # $buildResults = & dotnet build $path

            }
        }
    }
} else {
    Write-Output "The folder ${folderspec} doesn't exist."
}
