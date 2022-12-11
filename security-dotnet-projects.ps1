$unableToBuild = 0
$packageConfig = 0
$deprecatedProjects = 0
$vulnerabilities = 0
$numProjects = 0

# Identify all CSPROJ files in the solution and scan for security
$files = Get-ChildItem -Path "." -Recurse -Filter "*.csproj"
foreach ($file in $files) {

    # Execute dotnet vulnerability scan and capture output
    Write-Output "Checking package $($file.FullName)..."
    $restore = & dotnet restore $file.FullName 2>&1
    $packagelist = & dotnet list $file.FullName package --vulnerable 2>&1
    $packagelist = $restore + $packagelist

    # Check type of response
    if ($packagelist -like "*has no vulnerable packages given the current sources*") {
        Write-Output "OK"
    } elseif ($packagelist -like "*uses package.config for NuGet packages*") {
        Write-Output "WARNING: $($file.FullName) uses package.config."
        $packageConfig++
    } elseif ($packagelist -like "*Unable to read a package reference from the project*") {
        Write-Output "ERROR: $($file.FullName) cannot be verified because it cannot be restored/built."
        $unableToBuild++
    } elseif ($packagelist -like "*Microsoft.WebApplication.targets"" was not found*") {
        Write-Output "ERROR: $($file.FullName) cannot be built because it is an out of support WebForms app."
        $deprecatedProjects++
    } elseif ($packagelist -like "*Microsoft.Silverlight.CSharp.targets"" was not found*") {
        Write-Output "ERROR: $($file.FullName) cannot be built because it is an out of support Silverlight app."
        $deprecatedProjects++
    } elseif ($packagelist -like "*has the following vulnerable packages*") {
        Write-Output "ERROR: $($file.FullName) has security vulnerabilities."
        $vulnerabilities++
    } else {
        Write-Output "Unknown vulnerability scan for $($file.FullName)"
        Write-Output $packagelist
    }
    $numProjects++
}

# Print summary
Write-Output "*******************************************************"
Write-Output "Checked $($numProjects) projects."
if ($vulnerabilities -gt 0) {
    Write-Output "Found $($vulnerabilities) projects with security vulnerabilities"
    Write-Error "Found $($vulnerabilities) projects with security vulnerabilities"
}
if ($unableToBuild -gt 0) {
    Write-Output "Found $($unableToBuild) projects that could not be restored / built"
    Write-Error "Found $($unableToBuild) projects that could not be restored / built"
}
if ($packageConfig -gt 0) {
    Write-Output "Found $($packageConfig) projects using outdated package.config files"
    Write-Error "Found $($packageConfig) projects using outdated package.config files"
}
if ($deprecatedProjects -gt 0) {
    Write-Output "Found $($deprecatedProjects) projects using deprecated WebForms or SilverLight"
    Write-Error "Found $($deprecatedProjects) projects using deprecated WebForms or SilverLight"
}
