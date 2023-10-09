# Invoke-SMBRemoting
Interactive Shell and Command Execution over Named-Pipes (SMB)

Invoke-SMBRemoting utilizes the SMB protocol to establish a connection with the target machine, and sends commands (and receives outputs) using Named Pipes.

Note: The user you run the script as needs to be administrator over the target system

Run as follows:

```
iex(new-object net.webclient).downloadstring('https://raw.githubusercontent.com/Leo4j/Invoke-SMBRemoting/dev/Invoke-SMBRemoting.ps1')
```

### Interactive Shell
```
Enter-SMBSession -ComputerName "Workstation-01.ferrari.local"
```
```
Enter-SMBSession -ComputerName "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService
```

### Command Execution
```
Enter-SMBSession -ComputerName "Workstation-01.ferrari.local" -Command whoami
```
```
Enter-SMBSession -ComputerName "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService -Command whoami
```

![image](https://github.com/Leo4j/Invoke-SMBRemoting/assets/61951374/5262c28a-f375-42ef-8f59-ddceb2edad8a)


