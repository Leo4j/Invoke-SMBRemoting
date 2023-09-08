# Invoke-SMBRemoting
Command Execution or Interactive Shell over Named-Pipes (SMB)

Invoke-SMBRemoting utilizes the SMB protocol to establish a connection with the target machine, and sends commands (and receives outputs) using Named Pipes.

It begins by initiating a temporary service on the target system. On session completion (or upon receiving an exit command), the tool executes a disconnection procedure, terminating the temporary service on the target. An integrated monitoring system ensures the service's deletion if the session unexpectedly terminates.

Note: The user you run the script as needs to be administrator over the target system

Run the same script on the target and client system as follows:

```
iex(new-object net.webclient).downloadstring('https://raw.githubusercontent.com/Leo4j/Invoke-SMBRemoting/main/Invoke-SMBRemoting.ps1')
```

### Interactive Shell
```
Invoke-SMBRemoting -Target "Workstation-01.ferrari.local"
```
```
Invoke-SMBRemoting -Target "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService
```

![image](https://github.com/Leo4j/Invoke-SMBRemoting/assets/61951374/8415c30a-14f8-44a8-b3f4-840fbebc3c4e)

### Command Execution
```
Invoke-SMBRemoting -Target "Workstation-01.ferrari.local" -Command whoami
```
```
Invoke-SMBRemoting -Target "Workstation-01.ferrari.local" -PipeName Something -ServiceName RandomService -Command whoami
```

![image](https://github.com/Leo4j/Invoke-SMBRemoting/assets/61951374/4c5b39de-dc03-4bcb-952d-9acc0f61090b)

