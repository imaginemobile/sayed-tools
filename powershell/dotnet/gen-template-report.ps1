[cmdletbinding()]
param(
    [Parameter(Position=0)]
    [string[]]$searchTerm = @(
            'template','templates', 'ServiceStack.Core.Templates', 'BlackFox.DotnetNew.FSharpTemplates','libyear','libyear',
            'angular-cli.dotnet','Carna.ProjectTemplates','SerialSeb.Templates.ClassLibrary','Pioneer.Console.Boilerplate'),
    
    [Parameter(Position=1)]
    [switch]$skipReport,

    [Parameter(Position=2)]
    [string]$newtonsoftDownloadUrl = 'http://www.nuget.org/api/v2/package/Newtonsoft.Json/10.0.2',

    [Parameter(Position=3)]
    [string]$newtonsoftFilename = 'Newtonsoft.Json-10.0.2.nupkg',

    [Parameter(Position=4)]
    [switch]$publishJsonReport,

    [Parameter(Position=5)]
    [string]$publishUsername = $env:publishUsername,

    [Parameter(Position=6)]
    [string]$publishPassword = $env:publishPassword
)

function InternalGet-ScriptDirectory{
    split-path (((Get-Variable MyInvocation -Scope 1).Value).MyCommand.Path)
}

$scriptDir = InternalGet-ScriptDirectory

function Get-FullPathNormalized{
    [cmdletbinding()]
    param (
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]] $path
    )
    process {
        foreach($p in $path){
            if(-not ([string]::IsNullOrWhiteSpace($p))){
                $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
            }
        }
    }
}

function Load-NewtonsoftJson{
    [cmdletbinding()]
    param(
        [Parameter(Position=1)]
        [string]$newtonsoftDownloadUrl = 'http://www.nuget.org/api/v2/package/Newtonsoft.Json/10.0.2',

        [Parameter(Position=2)]
        [string]$newtonsoftFilename = 'Newtonsoft.Json-10.0.2.nupkg'
    )
    process{
        $extractPath = ExtractRemoteZip -downloadUrl $newtonsoftDownloadUrl -filename $newtonsoftFilename
        $expectedPath = (join-path $extractPath '\lib\net40\Newtonsoft.Json.dll')
        if(-not (test-path $expectedPath)){
            throw ('Unable to load newtonsoft.json from [{0}]' -f $expectedPath)
        }
        'Loading newtonsoft.json from file [{0}]' -f $expectedPath | Write-Verbose
        [Reflection.Assembly]::LoadFile($expectedPath)
        $global:machinesetupconfig.HasLoadedNetwonsoft = $true
    }
}

$scriptDir = ((InternalGet-ScriptDirectory) + "\")

[string]$ignoreFilePath = (join-path $scriptDir 'template.ignore.txt')

if(-not (test-path $ignoreFilePath)){
    thorw ('template ignore fild not found at: [0]' -f $ignoreFilePath)
}

[string[]]$packagesToExclude = (Get-Content $ignoreFilePath)

$global:machinesetupconfig = @{
    MachineSetupConfigFolder = (Join-Path $env:temp 'SayedHaMachineSetup')
    MachineSetupAppsFolder = (Join-Path $env:temp 'SayedHaMachineSetup\apps')
    RemoteFiles = (join-path $env:temp 'SayedHaMachineSetup\remotefiles')
    HasLoadedNetwonsoft = $false
}

function Get7ZipPath{
    [cmdletbinding()]
    param()
    process{
        (join-path $env:ProgramFiles '7-Zip\7z.exe')
    }
}

function EnsureFolderExists{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$path
    )
    process{
        foreach($p in $path){
            if(-not [string]::IsNullOrWhiteSpace($p) -and (-not (Test-Path $p))){
                New-Item -Path $p -ItemType Directory
            }
        }
    }
}

function GetLocalFileFor{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1,Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$filename,

        [Parameter(Position=2)]
        [int]$timeoutSec = 60
    )
    process{
        'GetLocalFileFor: url:[{0}] filename:[{1}]' -f $downloadUrl,$filename | Write-Verbose
        $expectedPath = (Join-Path $global:machinesetupconfig.RemoteFiles $filename)
        
        if(-not (test-path $expectedPath)){
            # download the file
            EnsureFolderExists -path ([System.IO.Path]::GetDirectoryName($expectedPath)) | out-null
            Invoke-WebRequest -Uri $downloadUrl -TimeoutSec $timeoutSec -OutFile $expectedPath -ErrorAction SilentlyContinue | Write-Verbose
        }

        if(-not (test-path $expectedPath)){
            throw ('Unable to download file from [{0}] to [{1}]' -f $downloadUrl, $expectedPath)
        }

        $expectedPath
    }
}

function ExtractRemoteZip{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$downloadUrl,

        [Parameter(Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$filename
    )
    process{
        $zippath = GetLocalFileFor -downloadUrl $downloadUrl -filename $filename
        $expectedFolderpath = (join-path -Path ($global:machinesetupconfig.MachineSetupConfigFolder) ('apps\{0}\' -f $filename))

        if(-not (test-path $expectedFolderpath)){
            EnsureFolderExists -path $expectedFolderpath | Write-Verbose
            # extract the folder to the directory
            & (Get7ZipPath) x -y "-o$expectedFolderpath" "$zippath" | Write-Verbose
        }        

        # return the path to the folder
        $expectedFolderpath
    }
}

function GetTemplatesToCheck(){
    [cmdletbinding()]
    param(
        [string[]]$searchTerm =@('template','templates')
    )
    process{
        $allResults = @()
        foreach($st in $searchTerm){        
            $cmdToRun = '"{0}" list -Noninteractive -Prerelease {1}' -f (get-nuget),$st
            'cmdToRun: [{0}]' -f $cmdToRun | Write-Verbose 
            
            #$result = (Execute-CommandString -command $cmdToRun|%{$res = ($_.split(' '));if( ($res -ne $null) -and ($res.length -gt 1)) {
            #        @{
            #            'Name'=$res[0]
            #            'Version'=$res[1]                      
            #            'DownloadUrl' = (('https://api.nuget.org/packages/{0}.{1}.nupkg' -f $res[0],$res[1]).ToLower())
            #        }}})

            $result = (Execute-Command -exePath ('"{0}"' -f (get-nuget)) -arguments ('list -Noninteractive -Prerelease {0}' -f $st))|%{$res = ($_.split(' '));if( ($res -ne $null) -and ($res.length -gt 1)) {
                    @{
                        'Name'=$res[0]
                        'Version'=$res[1]                      
                        'DownloadUrl' = (('https://api.nuget.org/packages/{0}.{1}.nupkg' -f $res[0],$res[1]).ToLower())
                    }}}



            if($LASTEXITCODE -eq 0){
                $allResults += $result
            }
            else{
                throw ('Unknown error: ' + $Error[0])
            }
        }

        $filteredResults = @()
        foreach($pkg in $allResults){
            if(-not ($packagesToExclude.Contains($pkg.Name) )) {
                $filteredResults += $pkg
            }
        }

        "filteredResults:`n{0}" -f ($filteredResults|out-string) | Write-Verbose
        $global:filteredResults = $filteredResults
        $filteredResults
    }
}

function Get-PackageDownloadStats(){
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$package,
        [string]$urlformat = 'http://www.nuget.org/packages/{0}/',
        [int]$timeoutSec = 60
    )
    process{
        # $html = (Invoke-WebRequest -Uri 'http://www.nuget.org/packages/SlowCheetah/').rawcontent
        foreach($pkgobj in $package){
            [string]$pkgname = $pkgobj.Name
            [int]$dlcount = -1;
            [string]$packageurl = ($urlformat -f $pkgname)

            try{
                $response = (Invoke-WebRequest -Uri $packageurl -TimeoutSec $timeoutSec -ErrorAction SilentlyContinue )
                if($response -ne $null){
                    [string]$html = ($response.rawcontent)
                    if(-not([string]::IsNullOrWhiteSpace($html))) {
                        $htmllines = $html.split("`n")

                        # $dlpattern = '.*current version\)\s+([0-9,]+)\s[0-9]+\/.*'
                        $dlpattern = '([0-9,]+)\s+total downloads'
                        $dlcount = -1
                        try{
                            # $dlcount = ([regex]::Match($response.ParsedHtml.getElementById('version-history').innerText,$dlpattern)).Groups[1].Value
                            $dlcount = ([regex]::Match($response.RawContent,$dlpattern)).Groups[1].Value
                        }
                        catch{}
                        #$dlstring = (((( $htmllines|Select-String '<p class="stat-label">Downloads</p>' -SimpleMatch -Context 1))) | Select-Object -ExpandProperty Context | Select-Object -ExpandProperty PreContext)
                        #if($dlstring -match '<p class="stat-number">([0-9,]+)<\/p>'){
                        #    $dlcount = ($Matches[1])
                        #}
                        if($dlcount -eq -1){
                            'problem, package [{0}]' -f $packageurl | Write-Host -ForegroundColor Cyan
                        }
                        $downloadUrl = $pkgobj.DownloadUrl
                    }
            
                    New-Object -TypeName psobject -Property @{
                        'Name'=$pkgname
                        'DownloadCount'=$dlcount
                        'Downloadurl'=$downloadUrl
                        'Version'=$pkgobj.Version
                        'ExtractPath'=[string]$null
                        'NuspecPath'=[string]$null
                    }
                }
                else{
                    'No web result from url [{0}]' -f $packageurl | Write-Verbose
                }
            }
            catch{
                $_.Exception | Write-Verbose
            }
        }
    }
}

function Find-TemplateFilesUnderPath{
    [cmdletbinding()]
    param(
        [string[]]$path
    )
    process{
        foreach($pathToCheck in $path){
            if( -not ([string]::IsNullOrWhiteSpace($pathToCheck))){
                [string[]]$templateFiles = (Get-ChildItem $pathToCheck .template.config -Directory -Recurse|%{Get-ChildItem (get-item ($_).fullname) template.json -File}).FullName
            }
            # return the result
            $templateFiles
        }
    }
}

function Test-PathContainsTemplate(){
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string]$pathToCheck
    )
    process{
        if(test-path $pathToCheck){
            # if the folder contains a template return the path, otherwise return nothing.
            #[string[]]$templateFiles = (Get-ChildItem $pathToCheck .template.config -Directory -Recurse|%{Get-ChildItem (get-item ($_).fullname) template.json -File})
            [string[]]$templateFiles = Find-TemplateFilesUnderPath -path $pathToCheck
            if( ($templateFiles -ne $null) -and ($templateFiles.Length -gt 0)){
                # return the folder path
                $true
            }
            else{
                $false
            }
        }
    }
}

function Find-PathContainingTemplate(){
    [cmdletbinding()]
    param(
        [Parameter(Position=1,ValueFromPipeline)]
        [string[]]$pathToCheck
    )
    process{
        foreach($folderpath in $pathToCheck){
            # if the folder contains a template return the path, otherwise return nothing.
            $templateFiles = (Get-ChildItem $path .template.config -Directory -Recurse|%{Get-ChildItem (get-item ($_).fullname) template.json -File})
            if($templateFiles -ne $null -and ($templateFiles.Length -gt 0)){

                # return the folder path
                $folderpath
            }
        }
    }
}

function Get-TemplateReport{
    [cmdletbinding()]
    param(
        [string[]]$searchTerm = @('template','templates')       
    )
    process{
        # list of templates to check
        [int]$index = 0
        $searchResults = GetTemplatesToCheck -searchTerm $searchTerm
        $pkgs = ($searchResults |
                    ForEach-Object {
                        Write-Progress -Activity 'Finding templates' -PercentComplete ( (++$index)/($searchResults.length)*100 ) -Status ('{0} of {1}' -f $index,$searchResults.Length)
                        Get-PackageDownloadStats -package $_ })
        
        [object[]]$foundTemplatePackages = @()
        [string[]]$pathsToCheck = @()
        # download packages locally and get path to installed location
        $index = 0
        $totalNum = $pkgs.length
        foreach($pkg in $pkgs){
            Write-Progress -Activity 'Gathring template data' -PercentComplete ( (++$index)/$totalNum*100  ) -Status ('{0} of {1}' -f $index,$totalNum)

            $filename = '{0}-{1}.nupkg' -f $pkg.Name,$pkg.Version
            $extractpath = ExtractRemoteZip -downloadUrl $pkg.DownloadUrl -filename $filename
            $nuspecpath = (join-path $extractpath ('{0}.nuspec' -f $pkg.Name))
            'extractpath: {0}' -f $extractpath | Write-Verbose
            # $pathsToCheck += $extractpath
            if( (Test-PathContainsTemplate -pathToCheck $extractpath) -eq $true){
                $pkg.ExtractPath = $extractpath
                $pkg.NuspecPath = $nuspecpath
                $pkg
            }
        }
    } 
}

<#
.SYNOPSIS
    This will return nuget from the $cachePath. If it is not there then it
    will automatically be downloaded before the call completes.
#>
function Get-Nuget{
    [cmdletbinding()]
    param(
        $toolsDir = (Get-FullPathNormalized -path (join-path $scriptDir '../../contrib/')),
        $nugetDownloadUrl = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe'
    )
    process{
        if(!(Test-Path $toolsDir)){
            New-Item -Path $toolsDir -ItemType Directory | Write-Verbose
        }

        $nugetDestPath = Join-Path -Path $toolsDir -ChildPath nuget.exe

        if(!(Test-Path $nugetDestPath)){
            'Downloading nuget.exe' | Write-Verbose
            Invoke-WebRequest -Uri $nugetDownloadUrl -OutFile $nugetDestPath | Write-Verbose
            
            # (New-Object System.Net.WebClient).DownloadFile($nugetDownloadUrl, $nugetDestPath) | Out-Null

            # double check that is was written to disk
            if(!(Test-Path $nugetDestPath)){
                throw 'unable to download nuget'
            }
        }

        # return the path of the file
        (get-item $nugetDestPath).FullName
    }
}

function Execute-Command {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [String]$exePath,
        [Parameter(Mandatory = $true,Position=1,ValueFromPipelineByPropertyName=$true)]
        [String]$arguments,
        [Parameter(Position=2)]
        [System.IO.FileInfo]$workingDirectory
        )
    process{
        $psi = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError=$true
        $psi.FileName = $exePath
        $psi.Arguments = $arguments
        if($workingDirectory -and (Test-Path -Path $workingDirectory)) {
            $psi.WorkingDirectory = $workingDirectory
        }

        $process = New-Object -TypeName System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.EnableRaisingEvents=$true

        # Register the event handler for error
        $stdErrEvent = Register-ObjectEvent -InputObject $process  -EventName 'ErrorDataReceived' -Action {
            if (! [String]::IsNullOrEmpty($EventArgs.Data)) {
             $EventArgs.Data | Write-Error 
            }
        }

        # Starting process.
        $process.Start() | Out-Null
        $process.BeginErrorReadLine() | Out-Null
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit() | Out-Null
        $output | Write-Output
        
        # UnRegister the event handler for error
        Unregister-Event -SourceIdentifier $stdErrEvent.Name | Out-Null
    }
}

function Execute-CommandString{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [string[]]$command,
        
        [switch]
        $useInvokeExpression,

        [switch]
        $ignoreErrors
    )
    process{
        foreach($cmdToExec in $command){
            'Executing command [{0}]' -f $cmdToExec | Write-Verbose
            if($useInvokeExpression){
                try {
                    Invoke-Expression -Command $cmdToExec
                }
                catch {
                    if(-not $ignoreErrors){
                        $msg = ('The command [{0}] exited with exception [{1}]' -f $cmdToExec, $_.ToString())
                        throw $msg
                    }
                }
            }
            else {
                cmd.exe /D /C $cmdToExec

                if(-not $ignoreErrors -and ($LASTEXITCODE -ne 0)){
                    $msg = ('The command [{0}] exited with code [{1}]' -f $cmdToExec, $LASTEXITCODE)
                    throw $msg
                }
            }
        }
    }
}

function Get-JsonObjectFromTemplateFile{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]]$templateFilePath
    )
    process{
        if(-not ($global:machinesetupconfig.HasLoadedNetwonsoft)){
            Load-NewtonsoftJson | Write-Verbose            
        }
        
        foreach($filepath in $templateFilePath){
            if(-not (Test-Path $filepath -PathType Leaf)){
                continue;
            }

            if($filepath.tolower().contains('sharp')){
                'break here' | Write-Output
            }
            
            try{
                $json = [System.IO.File]::ReadAllText($filepath)
                $jObj2 = [Newtonsoft.Json.Linq.JObject]::Parse($json)

                $result = New-Object -TypeName psobject -Property @{ 
                    author=[string]$jObj2.author.Value
                    symbols=$jObj2.symbols
                    classifications=[string[]]($jObj2.classifications|%{$_.Value})
                    name=[string]$jObj2.name.Value
                    identity=[string]$jObj2.identity.Value
                    groupIdentity=[string]$jObj2.groupIdentity.Value
                    shortName = [string]$jObj2.shortName.Value
                    tags = @{}
                }
                
                if($jObj2.tags -ne $null){
                    $jObj2.tags|%{
                        $result.tags.Add($_.Name,$_.Value.ToString())
                    }
                }
                $result
            }
            catch{
                'Error reading file [{0}]. Error [{1}]' -f $filepath,$_.Exception | Write-Warning
            }
        }
    }
}

function Get-PackageTemplateStats{
    [cmdletbinding()]
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [object[]]$package
    )
    process{
        'Start Looking at package: {0}' -f $package | Write-Verbose
        foreach($pkg in $package){
        '   Looking at package: {0}' -f $pkg | Write-Verbose
            if($pkg -eq $null){
                'skipping becaus package is null' | Write-Verbose
                continue
            }

            $pkgExtractPath = $pkg.ExtractPath

            if(-not ([string]::IsNullOrWhiteSpace($pkgExtractPath)) -and (test-path $pkgExtractPath)){
                # find template files under this path
                [string[]]$templateFiles = Find-TemplateFilesUnderPath -path $pkgExtractPath

                [object[]]$templateFileObj = Get-JsonObjectFromTemplateFile -templateFilePath $templateFiles
                if( ($templateFileObj -ne $null) -and ($templateFileObj.length -gt 0)){
                    $result = new-object -TypeName psobject -Property @{
                        Package=$pkg.Name
                        Version = $pkg.Version
                        DownloadCount = $pkg.DownloadCount
                        DownloadUrl = $pkg.DownloadUrl
                        ExtractPath = $pkg.ExtractPath
                        Description = [string]$null
                        ProjectUrl = [string]$null
                        IconUrl = [string]$null
                        LicenseUrl = [string]$null
                        Copyright = [string]$null
                        Owners = [string]$null
                        Authors = [string]$null
                        Tags = [string]$null
                        Templates = @()
                    }

                    if( $pkg.NuspecPath -ne $null -and (-not([string]::IsNullOrWhiteSpace($pkg.NuspecPath))) -and (test-path $pkg.NuspecPath)) {
                        try{
                            [xml]$nuspec = (get-content $pkg.NuspecPath)
                            $result.Description = $nuspec.package.metadata.description
                            $result.ProjectUrl = $nuspec.package.metadata.projectUrl
                            $result.IconUrl = $nuspec.package.metadata.iconUrl
                            $result.LicenseUrl = $nuspec.package.metadata.licenseUrl
                            $result.Copyright = $nuspec.package.metadata.copyright
                            $result.Owners = $nuspec.package.metadata.owners
                            $result.Authors = $nuspec.package.metadata.authors
                            $result.Tags = $nuspec.package.metadata.tags
                        }
                        catch{
                            'Unable to read nuspec at [{0}]. Error: [{1}]' -f $pkg.NuspecPath, $_.Exception | Write-Warning
                        }
                    }
                    else{
                        '*** nuspec not found or empty [{0}]' -f $pkg.NuspecPath | Write-Verbose
                    }

                    foreach($template in $templateFileObj){
                        $tobject = New-Object psobject -Property @{
                            author = $template.author
                            classifications = [string[]]($template.classifications)
                            name = $template.name
                            identity = $template.identity
                            groupIdentity = $template.groupIdentity
                            shortName = $template.shortName
                            tags = $template.tags # [string[]]@() #($tempalte.tags|%{$_.ToString()})
                            # parameters = ($template.symbols|%{$_.ToString()})
                        }
<#
                        if($template.tags -ne $null){
                            foreach($tt in $tempalte.tags){
                                if($tt -ne $null){
                                    $tobject.tags += $tt.ToString()
                                }
                            }
                        }
#>

                        $result.Templates += $tobject
                        <#
                        author=$jObj2.author.Value
                    symbols=$jObj2.symbols
                    classifications=($jObj2.classifications|%{$_.Value})
                    name=$jObj2.name.Value
                    identity=$jObj2.identity.Value
                    groupIdentity=$jObj2.groupIdentity.Value
                    shortName = $jObj2.shortName.Value
                    tags = ($jObj2.tags|%{$_.ToString()})
                        #>
                    }

                    $result
                }
            }
            else{
                'Skipping because pkgExtractPath is empty' | Write-Verbose
            }
        }
    }
}

function Save-ToFileAsJson{
    [cmdletbinding()]
    param(
        [object]$jobject,
        [string]$filepath
    )
    process{
        if(test-path $filepath){
            Remove-Item -Path $filepath
        }
        
        $filestream = [System.IO.File]::CreateText($filepath)
        $serializer = New-Object -TypeName 'Newtonsoft.Json.JsonSerializer'
        $serializer.Serialize($filestream,$jobject)
        $filestream.Dispose()
    }
}

function Get-MSDeploy{
    [cmdletbinding()]
    param(
        [string]$msdeployPath = 'C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe'
    )
    process{
        if(test-path $msdeployPath) {
            Set-Alias -Name msdeploy -Value $msdeployPath -Scope Global
            return $msdeployPath
        }
        else {
            throw ('msdeploye.exe not found at [{0}]' -f $msdeployPath)
        }
    }
}

function Invoke-CommandString{
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [string[]]$command,
        
        [Parameter(Position=1)]
        $commandArgs,

        $ignoreErrors,

        [bool]$maskSecrets,

        [switch]$disableCommandQuoting
    )
    process{
        foreach($cmdToExec in $command){
            'Executing command [{0}]' -f $cmdToExec | Write-Verbose
            
            # write it to a .cmd file
            $destPath = "$([System.IO.Path]::GetTempFileName()).cmd"
            if(Test-Path $destPath){Remove-Item $destPath|Out-Null}
            
            try{
                $commandstr = $cmdToExec
                if(-not $disableCommandQuoting -and $commandstr.Contains(' ') -and (-not ($commandstr -match '''.*''|".*"' ))){
                    $commandstr = ('"{0}"' -f $commandstr)
                }

                '{0} {1}' -f $commandstr, ($commandArgs -join ' ') | Set-Content -Path $destPath | Out-Null

                $actualCmd = ('"{0}"' -f $destPath)
                cmd.exe /D /C $actualCmd

                if(-not $ignoreErrors -and ($LASTEXITCODE -ne 0)){
                    $msg = ('The command [{0}] exited with code [{1}]' -f $commandstr, $LASTEXITCODE)
                    throw $msg
                }
            }
            finally{
                if(Test-Path $destPath){Remove-Item $destPath -ErrorAction SilentlyContinue |Out-Null}
            }
        }
    }
}

function DeployTemplateReport{
    [cmdletbinding()]
    param(
        [string]$publishUsername = $env:publishUsername,
        [string]$publishPassword = $env:publishPassword,
        [string]$deployUrl = 'https://dotnetnew-api.scm.azurewebsites.net/msdeploy.axd?site=dotnetnew-api',
        [string]$sourceRelFilepath = 'template-report.json',
        [string]$destRelFilepath = 'wwwroot/wwwroot/template-report.json'
    )
    process{
    # msdeploy -verb:sync -whatif -source:contentPath='C:\data\mycode\sayed-tools\powershell\dotnet\template-report2.json' -dest:contentPath='wwwroot/template-report.json',ComputerName="https://dotnetnew-api.scm.azurewebsites.net/msdeploy.axd?site=dotnetnew-api",UserName='%pubusername%',Password='%pubpwd%',AuthType='Basic'

        if([string]::IsNullOrWhiteSpace($publishUsername)){
            throw '$publishUsername empty, cannot publish'
        }
        if([string]::IsNullOrWhiteSpace($publishPassword)){
            throw '$publishPassword empty, cannot publish'
        }

        # check that the source file is on disk
        [string]$sourceFile = join-path $scriptDir $sourceRelFilepath | Get-FullPathNormalized
        if(-not (test-path $sourceFile)){
            throw ('source file not found at [{0}], from relpath: [{1}]' -f $sourceFile, $sourceRelFilepath)
        }

        # msdeploy -verb:sync -whatif -source:contentPath=''{0}'' -dest:contentPath=''{1}'',ComputerName="{2}",UserName=''{3}'',Password=''{4}'',AuthType=''Basic'' -retryAttempts=10 -retryInterval=2000 

        [string]$msdeployCmdArgs = ('-verb:sync -source:contentPath=''{0}'' -dest:contentPath=''{1}'',ComputerName="{2}",UserName=''{3}'',Password=''{4}'',AuthType=''Basic'' -retryAttempts=10 -retryInterval=2000 ' -f $sourceFile,$destRelFilepath,$deployUrl,$publishUsername,$publishPassword)
        $logfilepath = "$([System.IO.Path]::GetTempFileName()).log"
        'Starting publish, logfile={0}' -f $logfilepath | Write-Output
        try{
            # wrap the call and grab all output. This is needed to mask any secrets that may appear in the logs
            Invoke-CommandString -command (Get-MSDeploy) -commandArgs $msdeployCmdArgs *> $logfilepath
        }
        catch{
        }
        $logcontent = Get-Content $logfilepath
        $logcontent.Replace($publishUsername,'***USERNAME***').Replace($publishPassword,'***PASSWORD***') | Write-Output
    }
}

function Print-Report{
    [cmdletbinding()]
    param(
        [object[]]$reportObj
    )
    process{
        $totalDownload = ($reportObj|Measure-Object -Property DownloadCount -Sum).sum
        $overallReportStrFormat = @'

*****************************************************
Total downloads: {0} 
Num authors:     {3}
Num packages:    {1}
Num templates:   {2}
*****************************************************

'@
        $overallReportStrFormat -f $totalDownload, $reportObj.Length, $reportObj.Templates.Length, ($reportObj.authors|Select-Object -Unique).length

        @"
`n*****************************************************
    Package Report
*****************************************************
"@ | Write-Output

        foreach($pkgR in $reportObj){
            @'
pkg={0} 
    Downloads: {1}
    Templates: {3}
'@ -f $pkgR.Package, $pkgR.DownloadCount, $pkgR.Templates.Length,(($pkgR.Templates|%{'{0}' -f $_.Name}) -join "`n               ") | Write-Host -NoNewline
            
            
            "`n" | Write-Output
    }
    
        @"
`n*****************************************************
    Package Owner Report
*****************************************************
"@ | Write-Output

    $reportObj.Owners|Select-Object -Unique| ForEach-Object {
        $cOwner = $_
        $items = $reportObj|Where-Object {$_.Owners -eq $cOwner}
        @'
owner={0}
  Downloads: {1}
  Packages:  {2}
  Templates: {4}
'@      -f $cOwner, ($items|Measure-Object -Property DownloadCount -Sum).Sum, (($items.Package|%{"$_"}) -join "`n             " ), $items.Templates.Count, (($items.Templates.name|%{"$_"}) -join "`n             " )  | Write-Output

        " " | Write-Output   
    }
    }
}

function Run-FullReport{
    [cmdletbinding()]
    param(
        [Parameter(Position=0)]
        [string[]]$searchTerm = @('template','templates')
    )
    process{
        $global:foundpackages = @()
        $global:foundpackages += ( Get-TemplateReport -searchTerm $searchTerm )

        $uResults = $Global:foundpackages|Select-Object -Unique -Property *|Sort-Object -Property DownloadCount -Descending
        $totalDownload = ($uResults|Measure-Object -Property DownloadCount -Sum).Sum

        ' --- template report ---' | Write-Output
        $uResults | Select-Object -Property Name,DownloadCount,@{Name='Percent overall';Expression={'{0:P1}' -f ($_.DownloadCount/$totalDownload)}}
        $global:sihuResults = $uResults
        # not working for some reason
        # " --- overall ---`n" | Write-Output
        # $uResults.DownloadCount|Measure-Object -Sum -Average -Maximum -Minimum

        [string[]]$templateFiles=@()
        $uResults.ExtractPath | ForEach-Object{
            $cpath = $_
            if(test-path $cpath){
                $templateFiles += (Find-TemplateFilesUnderPath -path $cpath)
            }
        }
        $global:sihtemplatefiles = $templateFiles
        "Found template files: [`n{0}]" -f ($templateFiles -join '`n') | Write-Verbose

        # $extractPath = $global:machinesetupconfig.MachineSetupAppsFolder
        # $templateFiles = Find-TemplateFilesUnderPath -path $extractPath
        <#
        "`n----------------------------------------------------" | Write-Output
        'Total downloads:.............. {0}' -f $totalDownload | Write-Output
        'Number of packages:............{0}' -f ($uResults.Length) | Write-Output
        'Number of templates:...........{0}' -f ($templateFiles.Length) | Write-Output
        #>

        $global:pkgReport = Get-PackageTemplateStats -package $uResults
        $reportPath = (join-path $scriptDir 'template-report.json')
        $global:pkgReport | ConvertTo-Json -Depth 100 | Out-File -FilePath $reportPath -Encoding ascii

        Print-Report -reportObj $global:pkgReport

        '*****************************************************' | Write-Host -ForegroundColor Cyan
        "`n --- template file details ---" | Write-Output
        $reportData = ($templateFiles | Get-JsonObjectFromTemplateFile | Select-Object -Property *,@{Name='Parameters';Expression={$_.symbols}} | Sort-Object -Property author)
        $global:sihReportData = $reportData
        $reportData | Format-List -GroupBy author



        if($env:APPVEYOR -eq $true){
            Push-AppveyorArtifact -path $reportPath -Filename 'template-report.json'
        }
    }
}

try{
    if(-not ($skipReport)){
        & (get-nuget) update -self
        Run-FullReport -searchTerm $searchTerm

        if($publishJsonReport){
            DeployTemplateReport
        }

    }
}
catch{
    $_.Exception | Write-Error
}
