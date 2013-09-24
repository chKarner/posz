$script:zscore = @();
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$zscoreFile = "$scriptDir\zscores.csv"

if(test-path $zscoreFile){
$script:zscore = @(import-csv $zscoreFile)
}

function cd2 {
    param($path)
    if(-not $path){
        # Go Home
        Set-Location "~"
        return;
    }
    
    $fullpath = resolve-path $path
    
    $existingPath = $script:zscore | ?{ $_.path.tostring() -eq $fullpath}
    if($existingPath){
        $existingPath.frequency = [convert]::toint32($existingPath.frequency) + 1
        $existingPath.recent = [convert]::toint32($existingPath.recent) + 10
    } else{
        $newPath = new-object psobject
        $newPath | add-member -name path -type noteproperty -value $fullpath
        $newPath | add-member -name frequency -type noteproperty -value 1
        $newPath | add-member -name recent -type noteproperty -value 10
        $script:zscore +=  $newPath
    }
    
    $recentSum = ($zscore | measure-object -Property recent -Sum).Sum
    if($recentSum -ge 1000){
        $script:zscore | %{ $_.recent = [math]::floor([convert]::toint32($_.recent) * 0.9) }
        $script:zscore = $script:zscore | ?{ $_.recent -ge 1}
    }
    
    $zscore | export-csv $zscoreFile -notypeinformation
    
    set-location $path

}

set-alias -name cd -value cd2 -option AllScope

function zMatch ( $path, [switch] $ranked, [switch] $times){
    $expression = '$([convert]::toint32($_.frequency) * [convert]::toint32($_.recent))'
    if($ranked){
        $expression = '$([convert]::toint32($_.recent))'
    } elseif ($times){
        $expression = '$([convert]::toint32($_.frequency))'
    }

    # Escape backslashes in regex
    $path = $path -replace "\\","\\"
    
    return $zscore | ?{ $_ -match $path } | sort -property {iex $expression} -desc | select -first 1
}

function zTabExpansion($lastBlock) {
    # Remove command-alias from block
    $toExpand = $lastBlock -replace "^$(Get-AliasPattern z) ",""

    $pathFound = zMatch $toExpand

    if($pathFound){
        return $pathFound.path
    }
}

function z ( $path, [switch] $list, [switch] $ranked, [switch] $times){
    if($list){
        if(-not $path){
            return $script:zscore
        }
    }

    $pathFound = zMatch $path $ranked $times

    if($pathFound){
        cd $pathFound.path
    }
}

# Tab expansion, idea copied from posh-git (https://github.com/dahlbyk/posh-git)
if (Test-Path Function:\TabExpansion) {
    Rename-Item Function:\TabExpansion TabExpansionPreZ
}

function Get-AliasPattern($exe) {
   $aliases = @($exe) + @(Get-Alias | where { $_.Definition -eq $exe } | select -Exp Name)
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
