# Replace this value with your organization URL
$org = 'https://dev.azure.com/MyOrganizationNameGoesHere'

# Fetch list of projects
$projects = az devops project list --organization $org --query 'value[].name' -o tsv

# Clone all projects into the current folder via Azure DevOps / GIT
foreach ($proj in $projects) {
  $repos = az repos list --organization $org --project $proj | ConvertFrom-Json
  foreach ($repo in $repos) {
    if (-not (Test-Path -Path $Repo.name -PathType Container)) {
      Write-Warning -Message "Cloning repo $proj\$($repo.Name)"
      git clone $repo.webUrl
    }
  }
}

# Measure size of all repositories
foreach ($repo in Get-ChildItem ".") {
  $size = 0
  $files = 0
  foreach ($file in Get-ChildItem $repo -Recurse -Force -ErrorAction SilentlyContinue) {
    if ($file.FullName -like "*\.git\*") {
      # echo "Skipping file $file under git"
    } else {
      $size += $file.Length
      $files += 1
      # echo "Measuring $file : $size $files"
    }
  }
  $name = $repo.Name
  Write-Output "$($name),$($size),$($files)"
}