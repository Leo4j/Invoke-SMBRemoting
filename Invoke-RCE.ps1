function Invoke-RCE {
	
	<#

	.SYNOPSIS
	Invoke-RCE Author: Rob LP (@L3o4j)
	https://github.com/Leo4j/Invoke-RCE

	.DESCRIPTION
	Remote-Command-Execution over Named-Pipes
        The script must be run on both Target (Server) and local machine (Client)
	The user you run the script as Client needs to be Administrator over the target (Server)
	
	.PARAMETER Client
	Switch to run the script as the Client
	
	.PARAMETER Server
	Switch to run the script as the Server
	
	.PARAMETER PipeName
	Specify the PipeName (needs to match on both Client and Server)
	
	.PARAMETER Target
	The Server HostName or IP to connect to
	
	.EXAMPLE
	# Server
 	Invoke-RCE -Server
	Invoke-RCE -Server -PipeName Something

 	# Client
	Invoke-RCE -Client -Target "Workstation-01.ferrari.local"
 	Invoke-RCE -Client -Target "Workstation-01.ferrari.local" -PipeName Something
	
	#>

	param (
		[switch]$Client,
		[switch]$Server,
		[string]$PipeName = "MyUniquePipeName",  # Default value set here
		[string]$Target
	)
	
	$ErrorActionPreference = "SilentlyContinue"
	$WarningPreference = "SilentlyContinue"
	
	if ($Server) {

		$pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream($PipeName, 'InOut', 1, 'Byte', 'None', 1024, 1024, $null)

		$pipeServer.WaitForConnection()

		$sr = New-Object System.IO.StreamReader($pipeServer)
		$sw = New-Object System.IO.StreamWriter($pipeServer)

		while ($true) {
			$command = $sr.ReadLine()

			if ($command -eq "exit") {
				$sw.WriteLine("Exiting...")
				$sw.Flush()
				break
			} else {
				$result = Invoke-Expression $command

				if ($result -is [System.Array]) {
					foreach ($line in $result) {
						$sw.WriteLine($line)
					}
				} else {
					$sw.WriteLine($result)
				}

				$sw.WriteLine("###END###")  # Delimiter indicating end of command result
				$sw.Flush()
			}
		}

		$pipeServer.Disconnect()
		$sr.Close()
		$sw.Close()

	} elseif ($Client) {
		
		if (-not $Target) {
			Write-Output "Please specify a target"
			return
		}

		$pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream("$Target", $PipeName, 'InOut')
		$pipeClient.Connect()

		$sr = New-Object System.IO.StreamReader($pipeClient)
		$sw = New-Object System.IO.StreamWriter($pipeClient)

		$serverOutput = ""
		while ($true) {
			$userCommand = Read-Host "Enter Command"
			$sw.WriteLine($userCommand)
			$sw.Flush()

			if ($userCommand -eq "exit") {
				Write-Output ""
    				break
			}

			$serverOutput = ""
			while ($true) {
				$line = $sr.ReadLine()

				if ($line -eq "###END###") {  # Check for the delimiter
					Write-Output $serverOutput.Trim()  # Print the entire result at once
     					Write-Output ""
					break
				} else {
					$serverOutput += "$line`n"  # Accumulate the output until the delimiter is found
				}
			}
		}

		$sr.Close()
		$sw.Close()
	}
}
