$script:zscore = @();
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$zscoreFile = "$scriptDir\zscores.csv"

if(test-path $zscoreFile){
    $script:zscore = @(import-csv $zscoreFile)
}

function Get-UnixTime() {
    return [int][double]::Parse((Get-Date -UFormat %s))
}

function Get-FRecent($rank, $time) {
    # relate frequency and time
    $dx = Get-UnixTime - $time
    if ($dx -lt 3600) { return $rank * 4 }
    if ($dx -lt 86400) { return $rank * 2 }
    if ($dx -lt 604800) { return $rank / 2 }
    return $rank / 4
}

function Add-ZDir($path) {
    if(-not $path){
        return
    }

    $pathExists = Test-Path $path
    if(-not $pathExists) {
        return
    }

    $fullpath = Resolve-Path $path

    $existingPath = $script:zscore | Where-Object { $_.path.tostring() -eq $fullpath}
    if($existingPath){
        $existingPath.Rank = [convert]::toint32($existingPath.Rank) + 1
        $existingPath.Time = Get-UnixTime
    } else{
        $newPath = New-Object psobject
        $newPath | Add-Member -name Path -type noteproperty -value $fullpath
        $newPath | Add-Member -name Rank -type noteproperty -value 1
        $newPath | Add-Member -name Time -type noteproperty -value (Get-UnixTime)
        $script:zscore += $newPath
    }

    $recentSum = ($zscore | Measure-Object -Property Rank -Sum).Sum
    if($recentSum -ge 9000){
        $script:zscore | ForEach-Object { $_.Rank = [math]::floor([convert]::toint32($_.Rank) * 0.99) }
        $script:zscore = $script:zscore | Where-Object { $_.Rank -ge 1}
    }

    $zscore | export-csv $zscoreFile -notypeinformation
}

function zMatch ( $path ){
    # Escape backslashes in regex
    $path = $path -replace "\\","\\"
    
    return $zscore |
        Where-Object { $_ -match $path } |
        Select-Object -Property Path,@{
            Name="Recent"; Expression = {Get-FRecent $_.Rank  $_.Time}} |
        Sort-Object -property Recent -desc |
        Select-Object -first 1
}

function zTabExpansion($lastBlock) {
    # Remove command-alias from block
    $toExpand = $lastBlock -replace "^$(Get-AliasPattern z) ",""

    $pathFound = zMatch $toExpand

    if($pathFound){
        return $pathFound.Path
    }
}

function z ( $path, [switch] $list) {
    if ($list -or (-not $path)) {
        return $script:zscore
    }

    $pathFound = zMatch $path

    if($pathFound) {
        Set-Location $pathFound.Path
    }
}

# Tab expansion, idea copied from posh-git (https://github.com/dahlbyk/posh-git)
if (Test-Path Function:\TabExpansion) {
    Rename-Item Function:\TabExpansion TabExpansionPreZ
}

function Get-AliasPattern($exe) {
   $aliases = @($exe) + @(Get-Alias | Where-Object { $_.Definition -eq $exe } | Select-Object -Exp Name)
   "($($aliases -join '|'))"
}

function TabExpansion($line, $lastWord) {
    $lastBlock = [regex]::Split($line, '[|;]')[-1].TrimStart()

    switch -regex ($lastBlock) {
        # Execute z tab completion for all z aliases
        "^$(Get-AliasPattern z) (.*)" { zTabExpansion $lastBlock }

        # Fall back on existing tab expansion
        default { if (Test-Path Function:\TabExpansionPreZ) { TabExpansionPreZ $line $lastWord } }
    }
}
