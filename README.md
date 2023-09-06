# Invoke-RCE
Remote-Command-Execution over NamedPipes

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

Note: The user you run the script as (client) needs to be administrator over the target system (server)

```
Invoke-RCE -Client -Target "Workstation-01.ferrari.local"
```
```
Invoke-RCE -Client -Target "Workstation-01.ferrari.local" -PipeName Something
```
![image](https://github.com/Leo4j/Invoke-RCE/assets/61951374/12d296ab-aa18-4897-9a28-ade999921d4a)
