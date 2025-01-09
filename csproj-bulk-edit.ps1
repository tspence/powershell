param (
    [string][Parameter(Mandatory=$true, Position = 1)]$folder = ".",
    [string][Parameter(Mandatory=$true, Position = 2)]$property = $(throw "You must specify a property and a value to set for csproj files."),
    [string][Parameter(Mandatory=$true, Position = 3)]$value = $(throw "You must specify a property and a value to set for csproj files.")
)

function Usage() {
    Write-Output
    Write-Output "Usage:"
    Write-Output "    csproj-bulk-edit <folder> <property> <value>"
    Write-Output ""
    Write-Output "Parameters:"
    Write-Output "    <folder>   - The path to the folder to scan for .csproj files"
    Write-Output "    <property> - The property to change within each .csproj file"
    Write-Output "    <value>    - The value to set for the property"
    exit
}

# Does this folder exist?
if (-not (Test-Path -Path $folder)) {
    Write-Output "The folder '${folder}' doesn't exist."
    Usage
}

# Did the user provide a property and a value?
if (!$property -or !$value) {
    Write-Output "Please specify a property to set and a value to set it to."
    Usage
}

# Review all files in this folder and child folders
if (Test-Path -Path $folder) {
    foreach ($path in Get-ChildItem -Recurse "${folder}/**/*.csproj") {

        # Load XML using "preserve whitespace" so we can avoid unnecessary github changes
        $xml = [xml]::new()
        $xml.PreserveWhitespace = $true
        $xml.Load($path)

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
            $node = $propertyGroups[0].SelectSingleNode($property)
            if ($node) {
                Write-Output "The file '${path}' has project property group ${property} set to '${value}'"
            } else {
                Write-Output "Examining '${path}'..."

                # Preserve original file contents in case warnings-as-errors breaks this build
                $original = Get-Content $path
                Rename-Item -Path $path -NewName "${path}.old"

                # Construct the node with indentation before it, and a newline after it, so it looks appealing within the overall csproj file
                # Note that we don't need a newline beforehand, for some reason the preserve whitespace option would cause it to be a duplicate
                # Note that the previous whitespace element would already have indented us once
                # Also note that we want to use `r`n since we are running on Windows to avoid changing line endings for the file
                $newNodeText = "${indentation}<" + $property + ">" + $value + "</" + $property + ">`r`n${indentation}"
                $newNode = $xml.CreateDocumentFragment()
                $newNode.InnerXml = $newNodeText
                # We must save the results of this method call to a variable; otherwise it prints the function result to the console which looks ugly
                $_ = $xml.Project.PropertyGroup.AppendChild($newNode)
                $xml.Save($path)

                # Attempt to build the modified project
                $buildResults = & dotnet build $path 
                if ($?) {
                    Write-Output "Successfully built ${path} with new setting ${property} to '${value}'"
                    Remove-Item "${path}.old"
                } else {
                    Write-Output "Unable to build ${path} with the updated property setting, reverting change."
                    Set-Content -Path $path $original
                    Remove-Item $path
                    Rename-Item -Path "${path}.old" -NewName $path
                }
            }
        }
    }
} else {
}
