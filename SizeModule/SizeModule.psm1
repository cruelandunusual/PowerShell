function Get-Size {
    [CmdletBinding()]
    param(
        [Parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true)]
        [array]$List = '*',
        [string]$SortProperty = 'Size',
        [switch]$Descending,
        [switch]$Ascending
    )
    Begin {
        $paramError = $false
        try {
            if ($Descending -and $Ascending) {
                throw [System.ArgumentException]::new("Invalid argument combination passed")
            }
        }
        catch {
            Write-Error "$($_): can't specify both Ascending and Descending sort options at the same time"
            $paramError = $true
        }

        # Ansi escape codes for formatting output
        $KBColor = "`e[37m"   # White for KB
        $MBColor = "`e[33m"   # Yellow for MB
        $GBColor = "`e[36m"   # Cyan for GB
        $ResetColor = "`e[0m" # Reset formatting        
    }

    Process {
        if ($paramError) { return }
        $Output = @() # initialise the array to return
        $TotalSize = 0 # total size of each separate input object (i.e. file or folder) to be calculated
        # the following two variables are used by Write-Progress to calculate % completion
        $ListLength = $List.Count
        $counter = 0
    
        foreach ($ListItem in $List) {
            $Item = Get-Item $ListItem # need to explicitly get a handle to the item in case only a symbol is passed, e.g. .\Documents instead of $Documents
            $percent = ($counter / $ListLength) * 100
            Write-Progress -Activity "Calculating..." `
                -Status "Getting size of $($Item.Name)" `
                -PercentComplete $percent
            
            if ($Item -is [array]) {
                # if $Item is itself an array of items then Get-Size $Item will recursively get the size of each element
                if ($Descending) {
                    Get-Size $Item -SortProperty $SortProperty -Descending # pass Descending switch to the recursive function call
                }
                else {
                    Get-Size $Item -SortProperty $SortProperty
                }
            }
            else {
                $Type = "File"
                $Size = 0 # initialise a variable for the $Item's size every loop iteration
                if (!$Item.PSIsContainer) {
                    # it's a file so get its length property
                    $Size = $Item.Length
                }
                else {
                    # it's a folder so recursively compute the size of its contents
                    $Type = "Directory"
                    $Size = (Get-ChildItem -Recurse -Path $Item | Measure-Object -Property Length -Sum).Sum
                    
                    if ($null -eq $Size) {
                        # empty directory so no Lengths were -Summed; in this case we'll set $Size to zero
                        $Size = 0
                    }
                }
                $TotalSize += $Size
                $SizeResult = Get-SizeScale $Size # get a hashtable of size and scale factor for human-readability
                $SizeString = [string]$SizeResult.FileSize + ' ' + $SizeResult.Scale
                # Output is an array of custom objects
                $Output += [PSCustomObject]@{
                    Type       = $Type
                    Name       = $Item.Name
                    NameString = $Item.NameString
                    SizeString = $SizeString
                    Size       = $Size
                }
            }
            $counter++
        }
        
        # apply sorting logic - whether ascending or descending we
        # pipe the output array through Sort-Object with the appropriate flags
        # and overwrite the original array variable with the sorted version
        if ($Descending) {
            $Output = $Output | Sort-Object -Property $SortProperty -Descending
        }
        else {
            # default sort is ascending, no need to specify it
            $Output = $Output | Sort-Object -Property $SortProperty
        }
        # $Output is returned piped through Format-Table to enable colorizing of size values
        return $Output | Format-Table `
            'Type', `
        @{
            Name       = 'Name';
            Expression = { $_.NameString }
        },
        @{
            Name       = 'Size';
            Expression = {
                if ($_.SizeString -match 'KB') { "$KBColor$($_.SizeString)$ResetColor" }
                elseif ($_.SizeString -match 'MB') { "$MBColor$($_.SizeString)$ResetColor" }
                else { "$GBColor$($_.SizeString)$ResetColor" }
            };
            Alignment  = 'right'
        }
    }
    End {
    }
    <#
.SYNOPSIS
    Gets the size of a file or folder in a human-readable format
 
.DESCRIPTION
    `Get-Size` gets the size of a file or folder in a human-readable format.
    Output can be sorted by either file/folder name or size. Size is default.
    Output can be sorted Ascending or Descending. Ascending is default.
    Output is colorized by size for quick recognition; a separate color for items up to 1MB, items between 1MB and 1GB, and items larger than 1GB.
    Input can be multiple items in a comma-separated list of symbols,
    e.g. Get-Size D:\Audio, D:\Documents, myfile.txt
    as well as variables storing a list of items, e.g. Get-Size $mylist
     
.PARAMETER List
    `List` specifies the input list of items to be calculated
.PARAMETER SortProperty
    The `SortProperty` property specifies whether to sort by Name or Size. Default is Size. The syntax is:
    -SortProperty "Name" or -SortProperty Name
.PARAMETER Ascending/Descending
    Switch that specifies how to sort the list of results. Ascending is default so it can be ommitted.
    The syntax is:
    -Descending
.INPUTS
    `Get-Size` accepts pipeline input objects.
.OUTPUTS
    Object[]. Returns an array of PSCustomObjects. Outout is returned through Format-Table to enable colorized output.
.EXAMPLE
    $myfiles = Get-ChildItem D:\Documents\
    Get-Size $myfiles
.EXAMPLE
    Get-Size D:\Audio, $myfiles
.NOTES
    Output is returned through Format-Table and can't be usefully piped further.
#>    
}

<#
 Returns a hashtable containing the size of an item in GB, MB or KB,
 truncated to two decimal places, with an appropriate scale indicator
 as the second hashtable element
#>
function Get-SizeScale {
    param(
        [Parameter(Mandatory = $true)] # The parameter is mandatory
        $Size
    )
    $SizeScale = 'KB'
    if ($Size -gt 1GB) {
        $FileSizeFormatted = $Size / 1GB
        $SizeScale = 'GB'
    }
    elseif ($Size -gt 1MB) {
        $FileSizeFormatted = $Size / 1MB
        $SizeScale = 'MB'
    }
    else {
        $FileSizeFormatted = $Size / 1KB
    }
    $FileSizeFormatted = [math]::Round($FileSizeFormatted, 2) # truncate to two decimal places
    return @{
        FileSize = $FileSizeFormatted
        Scale    = $SizeScale
    }
}
