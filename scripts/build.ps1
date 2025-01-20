if ($null -eq $env:WINMD_BUILD_PARAMS) {
    $env:WINMD_BUILD_PARAMS = @("-s", "-t")
}

# Locations where Crystal could be installed
$locations = @("${env:ProgramFiles}\Crystal", "${env:CommonProgramFiles}\Crystal", "${env:LOCALAPPDATA}\Programs\Crystal")

ForEach($loc in $locations) {

    if (Test-Path -Path "${loc}\crystal.exe" -PathType Leaf) {
        $env:CRYSTAL_EXE = "${loc}\crystal.exe"
        $env:SHARDS_EXE = "${loc}\shards.exe"

        if (!$env:Path.Contains($loc)) {
            $env:Path = "${loc};${env:Path}"
        }
        break
    }


}

if ((Test-Path -Path ".\bin")) {
    Remove-Item -Path ".\bin" -Recurse -Force
    New-Item -ItemType Directory -Path ".\bin"
    Get-ChildItem -Path ".\bin"
}

$_build_params = @("build","-o","./bin/winmd.exe", "--static", "--release", "--progress")
$_build_params += $build_params
$_build_params += @("src/cli.cr")

& "$env:CRYSTAL_EXE" $_build_params